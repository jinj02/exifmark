#!/usr/bin/env python3
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlsplit
import zipfile


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import release


class FakeGitHub:
    def __init__(self, tag_commit=None, existing=None, fail_checksum=False):
        self.tag_commit = tag_commit
        self.release = deepcopy(existing)
        self.fail_checksum = fail_checksum
        self.calls = []
        self.next_asset = 1

    def request(self, method, path, data=None, **options):
        self.calls.append((method, path, deepcopy(data)))
        if method == 'GET' and path.startswith('/git/ref/tags/'):
            return dict(object=dict(type='commit', sha=self.tag_commit)) if self.tag_commit else None
        if method == 'GET' and path.startswith('/releases/tags/'):
            return deepcopy(self.release)
        if method == 'POST' and path == '/git/refs':
            self.tag_commit = data['sha']
            return dict(object=dict(type='commit', sha=self.tag_commit))
        if method == 'POST' and path == '/releases':
            self.release = dict(id=7, upload_url='https://uploads.github.com/repos/example/exifmark/releases/7/assets{?name,label}', assets=[], **data)
            return deepcopy(self.release)
        if method == 'PATCH' and path == '/releases/7':
            self.release.update(data)
            return deepcopy(self.release)
        if method == 'DELETE' and path.startswith('/releases/assets/'):
            asset_id = int(path.rsplit('/', 1)[1])
            self.release['assets'] = [asset for asset in self.release['assets'] if asset['id'] != asset_id]
            return None
        if method == 'POST' and path.startswith('https://uploads.github.com/'):
            name = parse_qs(urlsplit(path).query)['name'][0]
            if self.fail_checksum and name.endswith('.sha256'):
                self.fail_checksum = False
                raise release.ReleaseError('模拟校验文件上传失败。')
            asset = dict(id=self.next_asset, name=name, size=len(data), state='uploaded')
            self.next_asset += 1
            self.release['assets'].append(asset)
            return asset
        raise AssertionError(f'Unexpected API call: {method} {path}')


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='exifmark-release-tests-')
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name)
        self.run_git('init', '--initial-branch=main')
        self.run_git('config', 'user.name', 'Release Tests')
        self.run_git('config', 'user.email', 'tests@example.invalid')
        self.run_git('remote', 'add', 'upstream', 'https://github.com/example/exifmark.git')
        self.info_path = self.project / release.INFO_PATH
        self.info_path.parent.mkdir(parents=True)
        self.info_path.write_text('return { VERSION = { major = 0, minor = 0, revision = 0, build = 0 } }\n')
        (self.project / '.gitignore').write_text('.build/\ndist/\nrenderer/Sources/ExifmarkCLI/GeneratedBuildInfo.swift\n')
        (self.project / 'CHANGELOG.md').write_text(release.CHANGELOG_HEADER)
        self.commit('[feat] Initial plugin')
        self.initial = self.run_git('rev-parse', 'HEAD')

    def run_git(self, *arguments):
        return subprocess.check_output(
            ['git', '-C', str(self.project), *arguments], text=True, stderr=subprocess.PIPE
        ).strip()

    def commit(self, message, filename=None):
        if filename:
            path = self.project / filename
            path.write_text(path.read_text() + message + '\n' if path.exists() else message + '\n')
        self.run_git('add', '.')
        self.run_git('commit', '-m', message)

    def first_release(self):
        release.bump_version(self.project, 'minor')
        self.commit('chore(release): 0.1.0')
        return self.run_git('rev-parse', 'HEAD')

    def make_archive(self):
        information = release.build_info(self.project)
        archive = self.project / 'dist' / release.archive_name(information, True)
        archive.parent.mkdir(exist_ok=True)
        information.update(channel='release', archive=archive.name)
        packaged_info = release.replace_version(self.info_path.read_text(), release.source_version(self.project), information['build'])
        with zipfile.ZipFile(archive, 'w') as package:
            package.writestr('exifmark.lrplugin/build-info.json', json.dumps(information))
            package.writestr('exifmark.lrplugin/Info.lua', packaged_info)
        archive.with_suffix('.zip.sha256').write_text(
            f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n'
        )
        return archive

    def push_event(self, before=None):
        return dict(before=before or self.initial, after=self.run_git('rev-parse', 'HEAD'))

    def test_first_bump_collects_legacy_and_conventional_commits(self):
        self.commit('[fix] Fix existing export', 'fix.txt')
        self.commit('feat(layout): Add layout', 'layout.txt')
        self.commit('perf: Faster render', 'perf.txt')
        self.commit('docs: Install instructions', 'docs.txt')
        self.commit('fix!: Change interface\n\nBREAKING CHANGE: New interface', 'breaking.txt')
        self.commit('chore(release): internal bookkeeping', 'bookkeeping.txt')
        self.assertEqual(release.bump_version(self.project, 'minor'), '0.1.0')
        self.assertEqual(release.source_version(self.project), (0, 1, 0))
        notes = release.release_notes(self.project, '0.1.0')
        for heading in release.GROUPS:
            self.assertIn('### ' + heading, notes)
        self.assertIn('Initial plugin', notes)
        self.assertIn('Fix existing export', notes)
        self.assertIn('feat(layout): Add layout', notes)
        self.assertNotIn('bookkeeping', notes)
        self.assertIn('https://github.com/example/exifmark/commit/', notes)
        self.assertNotIn('diff --git', notes)

    def test_initial_release_is_fixed_at_point_one(self):
        for level in ('patch', 'major'):
            with self.subTest(level=level), self.assertRaises(release.ReleaseError):
                release.bump_version(self.project, level)
        self.assertEqual(release.source_version(self.project), (0, 0, 0))

    def test_repeated_bump_rejected_before_and_after_commit(self):
        release.bump_version(self.project, 'minor')
        with self.assertRaises(release.ReleaseError):
            release.bump_version(self.project, 'minor')
        self.commit('chore(release): 0.1.0')
        with self.assertRaises(release.ReleaseError):
            release.bump_version(self.project, 'patch')

    def test_patch_minor_major_and_changelog_boundaries(self):
        self.first_release()
        for level, target in (('patch', '0.1.1'), ('minor', '0.2.0'), ('major', '1.0.0')):
            previous = release.version_text(release.source_version(self.project))
            self.run_git('tag', 'v' + previous)
            self.commit(f'fix: Change for {target}', 'changes.txt')
            self.assertEqual(release.bump_version(self.project, level), target)
            notes = release.release_notes(self.project, target)
            self.assertIn(f'Change for {target}', notes)
            self.assertNotIn('Initial plugin', notes)
            self.assertNotIn('chore(release)', notes)
            self.commit(f'chore(release): {target}')
        document = (self.project / 'CHANGELOG.md').read_text()
        self.assertLess(document.index('[1.0.0]'), document.index('[0.2.0]'))
        self.assertIn('[0.1.0]', document)

    def test_dirty_tracked_files_block_bump(self):
        self.info_path.write_text(self.info_path.read_text() + '\n')
        with self.assertRaisesRegex(release.ReleaseError, '提交'):
            release.bump_version(self.project, 'minor')

    def test_shallow_history_rejected(self):
        self.commit('fix: Second commit', 'fix.txt')
        clone = self.project / 'shallow'
        subprocess.run(
            ['git', 'clone', '--quiet', '--depth=1', self.project.as_uri(), str(clone)], check=True,
        )
        with self.assertRaisesRegex(release.ReleaseError, '完整Git历史'):
            release.build_info(clone)

    def test_source_behind_tag_rejected(self):
        self.first_release()
        self.run_git('tag', 'v0.1.0')
        self.info_path.write_text(release.replace_version(self.info_path.read_text(), (0, 0, 0)))
        self.commit('chore: Reset version')
        with self.assertRaises(release.ReleaseError):
            release.bump_version(self.project, 'minor')

    def test_duplicate_changelog_rejected(self):
        document = self.project / 'CHANGELOG.md'
        document.write_text(document.read_text() + '\n## [0.1.0] - 2026-10-27\n\nExisting\n')
        self.commit('docs: Existing changelog')
        with self.assertRaisesRegex(release.ReleaseError, '重复升版'):
            release.bump_version(self.project, 'minor')

    def test_merge_commit_omitted_but_branch_changes_included(self):
        self.run_git('checkout', '-b', 'feature')
        self.commit('feat: Branch feature', 'feature.txt')
        self.run_git('checkout', 'main')
        self.commit('fix: Main fix', 'fix.txt')
        self.run_git('merge', '--no-ff', 'feature', '-m', 'feat: Merge feature branch')
        entries = release.changelog_entries(self.project)
        self.assertIn('Branch feature', entries)
        self.assertIn('Main fix', entries)
        self.assertNotIn('Merge feature branch', entries)

    def test_build_number_repeatability_and_generated_sources(self):
        self.commit('fix: Second commit', 'fix.txt')
        first = release.prepare_build(self.project)
        second = release.prepare_build(self.project)
        self.assertEqual(first, second)
        self.assertEqual(first['build'], 2)
        self.assertEqual(first['commit'], self.run_git('rev-parse', 'HEAD'))
        self.assertIn('build 2', release.cli_version(first))
        self.assertEqual(self.run_git('status', '--porcelain', '--untracked-files=no'), '')
        self.assertIn('0.0.0-build2-', release.archive_name(first))
        self.assertNotIn('build', release.archive_name(first, True))

    def test_development_pr_and_manual_events_do_not_publish(self):
        self.assertFalse(release.release_candidate(self.project, 'push', self.push_event(), 'refs/heads/main'))
        self.first_release()
        for event, ref in (('pull_request', 'refs/pull/1/merge'), ('workflow_dispatch', 'refs/heads/main'), ('push', 'refs/heads/feature')):
            with self.subTest(event=event, ref=ref):
                self.assertFalse(release.release_candidate(self.project, event, self.push_event(), ref))

    def test_version_change_publishes_only_verified_push_commit(self):
        head = self.first_release()
        self.assertTrue(release.release_candidate(self.project, 'push', self.push_event(), 'refs/heads/main'))
        self.run_git('tag', 'v0.1.0')
        self.assertTrue(release.release_candidate(self.project, 'push', self.push_event(), 'refs/heads/main'))
        self.commit('fix: Later change', 'later.txt')
        self.assertFalse(release.release_candidate(self.project, 'push', self.push_event(head), 'refs/heads/main'))
        with self.assertRaises(release.ReleaseError):
            release.release_candidate(self.project, 'push', self.push_event(), 'refs/heads/main')

    def test_mismatched_push_commit_and_missing_before_rejected(self):
        self.first_release()
        with self.assertRaises(release.ReleaseError):
            release.release_candidate(self.project, 'push', dict(before=self.initial, after='f' * 40), 'refs/heads/main')
        with self.assertRaises(release.ReleaseError):
            release.release_candidate(self.project, 'push', self.push_event('f' * 40), 'refs/heads/main')

    def test_initial_push_release_and_downgrade_rules(self):
        self.first_release()
        self.assertTrue(release.release_candidate(self.project, 'push', self.push_event('0' * 40), 'refs/heads/main'))
        self.info_path.write_text(release.replace_version(self.info_path.read_text(), (0, 2, 0)))
        self.commit('chore: Invalid initial version')
        higher = self.run_git('rev-parse', 'HEAD')
        with self.assertRaisesRegex(release.ReleaseError, '首个正式版本'):
            release.release_candidate(self.project, 'push', self.push_event(), 'refs/heads/main')
        self.info_path.write_text(release.replace_version(self.info_path.read_text(), (0, 1, 0)))
        self.commit('chore: Downgrade')
        with self.assertRaisesRegex(release.ReleaseError, '倒退'):
            release.release_candidate(self.project, 'push', self.push_event(higher), 'refs/heads/main')

    def test_ci_outputs_choose_matching_package_channel(self):
        self.first_release()
        event_path = self.project / '.build/event.json'
        event_path.parent.mkdir()
        event_path.write_text(json.dumps(self.push_event()))
        output = self.project / '.build/output'
        with patch.dict(os.environ, GITHUB_EVENT_NAME='push', GITHUB_REF='refs/heads/main', GITHUB_EVENT_PATH=str(event_path)):
            values = release.ci_context(self.project, output)
        self.assertEqual(values['release'], 'true')
        self.assertEqual(values['archive'], 'exifmark-0.1.0-macos.zip')
        self.assertIn('release=true\n', output.read_text())
        with patch.dict(os.environ, GITHUB_EVENT_NAME='pull_request', GITHUB_REF='refs/pull/1/merge', GITHUB_EVENT_PATH=str(event_path)):
            values = release.ci_context(self.project)
        self.assertEqual(values['release'], 'false')
        self.assertIn('-build2-', values['archive'])

    def test_missing_notes_block_release(self):
        self.first_release()
        (self.project / 'CHANGELOG.md').write_text('# Changelog\n')
        self.commit('docs: Remove notes')
        with self.assertRaisesRegex(release.ReleaseError, '更新说明'):
            release.release_candidate(self.project, 'push', self.push_event(), 'refs/heads/main')

    def test_publish_uploads_before_publication_and_is_idempotent(self):
        head = self.first_release()
        archive = self.make_archive()
        client = FakeGitHub()
        self.assertIn('发布完成', release.publish_release(self.project, archive, client))
        self.assertEqual(client.tag_commit, head)
        self.assertFalse(client.release['draft'])
        self.assertEqual({asset['name'] for asset in client.release['assets']}, {archive.name, archive.name + '.sha256'})
        self.assertEqual(client.calls[-1], ('PATCH', '/releases/7', dict(draft=False, make_latest='true')))
        client.calls.clear()
        self.assertIn('跳过', release.publish_release(self.project, archive, client))
        self.assertTrue(all(method == 'GET' for method, _, _ in client.calls))

    def test_failed_upload_stays_draft_and_rerun_completes(self):
        self.first_release()
        archive = self.make_archive()
        client = FakeGitHub(fail_checksum=True)
        with self.assertRaisesRegex(release.ReleaseError, '模拟'):
            release.publish_release(self.project, archive, client)
        self.assertTrue(client.release['draft'])
        self.assertEqual(len(client.release['assets']), 1)
        self.assertIn('发布完成', release.publish_release(self.project, archive, client))
        self.assertFalse(client.release['draft'])
        self.assertEqual(len(client.release['assets']), 2)
        self.assertEqual(sum(method == 'POST' and path == '/releases' for method, path, _ in client.calls), 1)

    def test_conflicting_remote_tag_or_draft_rejected(self):
        self.first_release()
        archive = self.make_archive()
        for client in (
            FakeGitHub(tag_commit=self.initial),
            FakeGitHub(existing=dict(target_commitish=self.initial, draft=True)),
        ):
            with self.subTest(client=client), self.assertRaises(release.ReleaseError):
                release.publish_release(self.project, archive, client)
            self.assertTrue(all(method == 'GET' for method, _, _ in client.calls))

    def test_published_release_with_missing_assets_rejected(self):
        head = self.first_release()
        archive = self.make_archive()
        client = FakeGitHub(tag_commit=head, existing=dict(draft=False, assets=[]))
        with self.assertRaisesRegex(release.ReleaseError, '附件不完整'):
            release.publish_release(self.project, archive, client)

    def test_archive_checksum_and_commit_must_match(self):
        self.first_release()
        archive = self.make_archive()
        archive.with_suffix('.zip.sha256').write_text('invalid\n')
        with self.assertRaisesRegex(release.ReleaseError, 'SHA-256'):
            release.publish_release(self.project, archive, FakeGitHub())
        archive = self.make_archive()
        self.commit('fix: Different source', 'later.txt')
        with self.assertRaisesRegex(release.ReleaseError, '提交不一致'):
            release.publish_release(self.project, archive, FakeGitHub())
        with self.assertRaisesRegex(release.ReleaseError, '缺少安装包'):
            release.publish_release(self.project, archive.with_name('missing.zip'), FakeGitHub())

    def test_http_errors_are_distinguished_from_missing_resources(self):
        client = release.GitHubClient('example/exifmark', 'test-token')
        for status in (401, 403, 500):
            with self.subTest(status=status), patch.object(release, 'urlopen', side_effect=HTTPError('https://api.github.com', status, 'error', None, None)):
                with self.assertRaises(release.ReleaseError):
                    client.request('GET', '/releases/tags/v0.1.0', allow_missing=True)
        with patch.object(release, 'urlopen', side_effect=HTTPError('https://api.github.com', 404, 'missing', None, None)):
            self.assertIsNone(client.request('GET', '/releases/tags/v0.1.0', allow_missing=True))


if __name__ == '__main__':
    unittest.main(verbosity=2)
