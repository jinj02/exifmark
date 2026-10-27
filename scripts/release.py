#!/usr/bin/env python3
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import zipfile
from zoneinfo import ZoneInfo


PROJECT_ROOT = Path(__file__).resolve().parents[1]
INFO_PATH = 'exifmark.lrplugin/Info.lua'
VERSION_PATTERN = re.compile(
    r'VERSION\s*=\s*\{\s*major\s*=\s*(\d+)\s*,\s*minor\s*=\s*(\d+)\s*,'
    r'\s*revision\s*=\s*(\d+)\s*,\s*build\s*=\s*(\d+)\s*\}'
)
TAG_PATTERN = re.compile(r'v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)')
COMMIT_PATTERN = re.compile(
    r'^(?:\[(?P<legacy>[\w-]+)\]|(?P<type>[\w-]+)(?:\((?P<scope>[^)]+)\))?'
    r'(?P<breaking>!)?:)\s*'
)
CHANGELOG_HEADER = '# 更新日志\n\n版本更新由升版命令根据Git提交记录生成。\n'
GROUPS = ('不兼容变更', '新增功能', '问题修复', '性能优化', '其他变更')


class ReleaseError(Exception):
    pass


def git(project_root, *arguments, check=True):
    result = subprocess.run(
        ['git', '-C', str(project_root), *arguments], capture_output=True, text=True
    )
    if check and result.returncode:
        raise ReleaseError(result.stderr.strip() or 'Git命令执行失败。')
    return result.stdout.rstrip('\n') if check else result


def require_history(project_root):
    if git(project_root, 'rev-parse', '--is-shallow-repository') != 'false':
        raise ReleaseError('需要完整Git历史；请先执行git fetch --unshallow --tags。')


def require_clean(project_root):
    if git(project_root, 'status', '--porcelain', '--untracked-files=no'):
        raise ReleaseError('请先提交已跟踪文件的改动，再执行升版或发布。')


def parse_version(contents):
    matches = list(VERSION_PATTERN.finditer(contents))
    if len(matches) != 1:
        raise ReleaseError('Info.lua必须包含唯一的major/minor/revision/build版本表。')
    return tuple(int(value) for value in matches[0].groups())


def version_text(version):
    return '.'.join(str(value) for value in version[:3])


def source_version(project_root):
    version = parse_version((project_root / INFO_PATH).read_text())
    if version[3] != 0:
        raise ReleaseError('源码中的build必须为0；构建号由Git历史自动生成。')
    if version[:3] != (0, 0, 0) and version[:3] < (0, 1, 0):
        raise ReleaseError('开发版本使用0.0.0，首个正式版本使用0.1.0。')
    return version[:3]


def replace_version(contents, version, build=0):
    parse_version(contents)
    replacement = (
        f'VERSION = {{ major = {version[0]}, minor = {version[1]}, '
        f'revision = {version[2]}, build = {build} }}'
    )
    return VERSION_PATTERN.sub(lambda match: replacement, contents, count=1)


def build_info(project_root):
    require_history(project_root)
    commit = git(project_root, 'rev-parse', 'HEAD')
    return dict(
        version=version_text(source_version(project_root)),
        build=int(git(project_root, 'rev-list', '--count', 'HEAD')),
        commit=commit,
        short_commit=commit[:12],
    )


def cli_version(information):
    return (
        f'exifmark-render {information["version"]} (build {information["build"]}, '
        f'commit {information["short_commit"]}; request v1)'
    )


def write_if_changed(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_text() != contents:
        path.write_text(contents)


def prepare_build(project_root):
    information = build_info(project_root)
    generated = project_root / 'renderer/Sources/ExifmarkCLI/GeneratedBuildInfo.swift'
    write_if_changed(
        generated,
        'enum BuildInfo {\n'
        f'    static let description = {json.dumps(cli_version(information))}\n'
        '}\n',
    )
    write_if_changed(
        project_root / '.build/build-info.json',
        json.dumps(information, indent=2) + '\n',
    )
    return information


def release_tags(project_root):
    versions = []
    for tag in git(project_root, 'tag', '--list').splitlines():
        match = TAG_PATTERN.fullmatch(tag)
        if match:
            version = tuple(int(value) for value in match.groups())
            if version >= (0, 1, 0):
                versions.append((version, tag))
    return sorted(versions)


def repository_url(project_root):
    for remote in ('origin', 'upstream'):
        result = git(project_root, 'remote', 'get-url', remote, check=False)
        if result.returncode == 0:
            match = re.fullmatch(
                r'(?:https://github\.com/|git@github\.com:)([\w.-]+/[\w.-]+?)(?:\.git)?',
                result.stdout.strip(),
            )
            if match:
                return 'https://github.com/' + match[1]
    raise ReleaseError('需要指向GitHub仓库的origin或upstream，以生成提交链接。')


def changelog_entries(project_root, previous_tag=None):
    revision = f'{previous_tag}..HEAD' if previous_tag else 'HEAD'
    history = git(
        project_root, 'log', '--no-merges', '--reverse',
        '--format=%H%x1f%s%x1f%b%x1e', revision,
    )
    groups = {group: [] for group in GROUPS}
    url = repository_url(project_root)
    for record in history.split('\x1e'):
        if not record.strip():
            continue
        commit, subject, body = record.strip('\n').split('\x1f', 2)
        match = COMMIT_PATTERN.match(subject)
        commit_type = (match['legacy'] or match['type']).lower() if match else ''
        if commit_type == 'release' or (
            match and commit_type == 'chore' and match['scope'] == 'release'
        ):
            continue
        if (match and match['breaking']) or re.search(r'^BREAKING[ -]CHANGE:', body, re.M):
            group = '不兼容变更'
        else:
            group = {
                'feat': '新增功能', 'feature': '新增功能',
                'fix': '问题修复', 'perf': '性能优化',
            }.get(commit_type, '其他变更')
        escaped = subject.replace('\\', '\\\\').replace('[', '\\[').replace(']', '\\]')
        groups[group].append(f'- {escaped} ([{commit[:7]}]({url}/commit/{commit}))')
    sections = [f'### {group}\n\n' + '\n'.join(groups[group]) for group in GROUPS if groups[group]]
    if not sections:
        raise ReleaseError('上次发布以来没有可写入更新文档的提交。')
    return '\n\n'.join(sections)


def bump_version(project_root, level):
    require_history(project_root)
    require_clean(project_root)
    current = source_version(project_root)
    tags = release_tags(project_root)
    previous_tag = tags[-1][1] if tags else None
    if not tags:
        if current != (0, 0, 0):
            raise ReleaseError('当前版本尚未发布，请先完成首次发布。')
        if level != 'minor':
            raise ReleaseError('首次正式升版请使用bump minor，生成0.1.0。')
        target = (0, 1, 0)
    else:
        if tags[-1][0] != current:
            raise ReleaseError('源码版本必须等于最新正式tag；请先同步或完成当前版本发布。')
        if git(project_root, 'merge-base', '--is-ancestor', previous_tag, 'HEAD', check=False).returncode:
            raise ReleaseError('当前提交必须包含最新正式tag的历史。')
        if level == 'major':
            target = (current[0] + 1, 0, 0)
        elif level == 'minor':
            target = (current[0], current[1] + 1, 0)
        else:
            target = (current[0], current[1], current[2] + 1)
    target_text = version_text(target)
    changelog_path = project_root / 'CHANGELOG.md'
    changelog = changelog_path.read_text() if changelog_path.exists() else CHANGELOG_HEADER
    if re.search(rf'^## \[{re.escape(target_text)}\]', changelog, re.M):
        raise ReleaseError(f'{target_text}的更新文档已存在，拒绝重复升版。')
    entries = changelog_entries(project_root, previous_tag)
    date = datetime.now(ZoneInfo('Asia/Shanghai')).date().isoformat()
    heading, separator, previous_sections = changelog.partition('\n## ')
    updated = heading.rstrip() + f'\n\n## [{target_text}] - {date}\n\n{entries}\n'
    if separator:
        updated += '\n## ' + previous_sections
    info_path = project_root / INFO_PATH
    info_path.write_text(replace_version(info_path.read_text(), target))
    changelog_path.write_text(updated)
    return target_text


def release_notes(project_root, version):
    path = project_root / 'CHANGELOG.md'
    if not path.is_file():
        raise ReleaseError('缺少CHANGELOG.md，请使用升版命令生成。')
    match = re.search(
        rf'^## \[{re.escape(version)}\][^\n]*\n(?P<body>.*?)(?=^## |\Z)',
        path.read_text(), re.M | re.S,
    )
    if not match or not match['body'].strip():
        raise ReleaseError(f'CHANGELOG.md缺少{version}的更新说明。')
    return match['body'].strip() + '\n'


def archive_name(information, formal=False):
    suffix = '' if formal else f'-build{information["build"]}-{information["short_commit"]}'
    return f'exifmark-{information["version"]}{suffix}-macos.zip'


def archive_path(project_root, formal=False):
    return project_root / 'dist' / archive_name(build_info(project_root), formal)


def package_plugin(project_root, formal=False):
    information = build_info(project_root)
    if formal and source_version(project_root) == (0, 0, 0):
        raise ReleaseError('0.0.0仅提供开发包。')
    binary = project_root / 'exifmark.lrplugin/bin/exifmark-render'
    actual = subprocess.check_output([str(binary), '--version'], text=True).strip()
    if actual != cli_version(information):
        raise ReleaseError('渲染器版本与当前源码不一致，请重新构建。')
    archive = project_root / 'dist' / archive_name(information, formal)
    archive.parent.mkdir(parents=True, exist_ok=True)
    information.update(channel='release' if formal else 'development', archive=archive.name)
    with tempfile.TemporaryDirectory(prefix='package-', dir=project_root / '.build') as folder:
        staging = Path(folder) / 'exifmark.lrplugin'
        for tracked_path in git(project_root, 'ls-files', '-z', '--', 'exifmark.lrplugin/').split('\0'):
            if tracked_path:
                destination = staging / Path(tracked_path).relative_to('exifmark.lrplugin')
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(project_root / tracked_path, destination)
        (staging / 'bin').mkdir()
        shutil.copy2(binary, staging / 'bin/exifmark-render')
        shutil.copytree(
            binary.parent / 'ExifmarkRenderer_ExifmarkCore.bundle',
            staging / 'bin/ExifmarkRenderer_ExifmarkCore.bundle',
        )
        info_path = staging / 'Info.lua'
        info_path.write_text(replace_version(info_path.read_text(), source_version(project_root), information['build']))
        (staging / 'build-info.json').write_text(json.dumps(information, indent=2) + '\n')
        readme_path = staging / 'README.txt'
        _, _, instructions = readme_path.read_text().partition('\n')
        readme_path.write_text(
            f'exifmark {information["version"]} (build {information["build"]}, '
            f'commit {information["short_commit"]})\n{instructions}'
        )
        temporary_archive = Path(folder) / archive.name
        subprocess.run(
            ['/usr/bin/ditto', '-c', '-k', '--keepParent', '--norsrc', '--noextattr',
             str(staging), str(temporary_archive)],
            env={**os.environ, 'COPYFILE_DISABLE': '1'}, check=True,
        )
        temporary_archive.replace(archive)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{checksum}  {archive.name}\n')
    return archive


def release_candidate(project_root, event_name, event, ref):
    current = source_version(project_root)
    if current == (0, 0, 0) or event_name != 'push' or ref != 'refs/heads/main':
        return False
    head = git(project_root, 'rev-parse', 'HEAD')
    if event.get('after') != head or event.get('deleted'):
        raise ReleaseError('push事件的提交与当前检出的提交不一致。')
    before = event.get('before', '')
    if before and set(before) != {'0'}:
        git(project_root, 'cat-file', '-e', f'{before}^{{commit}}')
        previous = git(project_root, 'show', f'{before}:{INFO_PATH}', check=False)
        previous_version = parse_version(previous.stdout)[:3] if previous.returncode == 0 else (0, 0, 0)
    else:
        previous_version = (0, 0, 0)
    if current == previous_version:
        return False
    if current < previous_version:
        raise ReleaseError('正式版本号发生倒退，拒绝发布。')
    tags = release_tags(project_root)
    for version, tag in tags:
        if version > current:
            raise ReleaseError('存在更高的正式tag，拒绝发布旧版本。')
        if version == current and git(project_root, 'rev-parse', f'{tag}^{{commit}}') != head:
            raise ReleaseError(f'{tag}已绑定其他提交。')
    if not any(version < current for version, _ in tags) and current != (0, 1, 0):
        raise ReleaseError('首个正式版本必须为0.1.0。')
    release_notes(project_root, version_text(current))
    return True


def ci_context(project_root, output=None):
    require_history(project_root)
    event_path = os.environ.get('GITHUB_EVENT_PATH')
    event = json.loads(Path(event_path).read_text()) if event_path else {}
    formal = release_candidate(
        project_root, os.environ.get('GITHUB_EVENT_NAME', ''), event,
        os.environ.get('GITHUB_REF', ''),
    )
    information = build_info(project_root)
    values = dict(
        version=information['version'], commit=information['commit'],
        archive=archive_name(information, formal),
        artifact=f'exifmark-macos-{information["commit"]}',
        release=str(formal).lower(),
    )
    if output:
        with Path(output).open('a') as stream:
            stream.write(''.join(f'{key}={value}\n' for key, value in values.items()))
    return values


class GitHubClient:
    def __init__(self, repository, token):
        if not re.fullmatch(r'[\w.-]+/[\w.-]+', repository):
            raise ReleaseError('GitHub仓库名必须为owner/repository。')
        if not token:
            raise ReleaseError('发布需要GITHUB_TOKEN。')
        self.base = f'https://api.github.com/repos/{repository}'
        self.token = token

    def request(self, method, path, data=None, allow_missing=False, content_type='application/json'):
        url = path if path.startswith('https://uploads.github.com/') else self.base + path
        payload = data if isinstance(data, bytes) else json.dumps(data).encode() if data is not None else None
        request = Request(url, data=payload, method=method, headers={
            'Authorization': f'Bearer {self.token}',
            'Accept': 'application/vnd.github+json',
            'Content-Type': content_type,
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'exifmark-release',
        })
        try:
            with urlopen(request, timeout=60) as response:
                contents = response.read()
                return json.loads(contents) if contents else None
        except HTTPError as error:
            if allow_missing and error.code == 404:
                return None
            raise ReleaseError(f'GitHub API请求失败：{method} {path.split("?")[0]}，HTTP {error.code}。') from error
        except URLError as error:
            raise ReleaseError(f'GitHub API连接失败：{error.reason}。') from error


def remote_tag_commit(client, tag):
    reference = client.request('GET', f'/git/ref/tags/{tag}', allow_missing=True)
    if reference is None:
        return None
    target = reference['object']
    for _ in range(10):
        if target['type'] == 'commit':
            return target['sha']
        if target['type'] != 'tag':
            break
        target = client.request('GET', f'/git/tags/{target["sha"]}')['object']
    raise ReleaseError(f'{tag}未指向有效提交。')


def validate_release_archive(project_root, archive):
    if not archive.is_file():
        raise ReleaseError(f'缺少安装包：{archive}')
    checksum_path = archive.with_suffix('.zip.sha256')
    expected = f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n'
    if not checksum_path.is_file() or checksum_path.read_text() != expected:
        raise ReleaseError('安装包SHA-256校验失败。')
    with zipfile.ZipFile(archive) as package:
        information = json.loads(package.read('exifmark.lrplugin/build-info.json'))
        packaged_version = parse_version(package.read('exifmark.lrplugin/Info.lua').decode())
    expected_info = build_info(project_root)
    if any(information.get(key) != value for key, value in expected_info.items()):
        raise ReleaseError('安装包的版本或提交与发布提交不一致。')
    if information.get('channel') != 'release' or archive.name != archive_name(expected_info, True):
        raise ReleaseError('发布需要正式安装包。')
    if packaged_version != (*source_version(project_root), information['build']):
        raise ReleaseError('安装包Info.lua版本不一致。')
    return information, checksum_path


def publish_release(project_root, archive, client):
    require_clean(project_root)
    information, checksum_path = validate_release_archive(project_root, archive)
    tag = 'v' + information['version']
    commit = information['commit']
    notes = release_notes(project_root, information['version'])
    target = remote_tag_commit(client, tag)
    if target is not None and target != commit:
        raise ReleaseError(f'{tag}已绑定其他提交，拒绝覆盖。')
    existing = client.request('GET', f'/releases/tags/{tag}', allow_missing=True)
    if existing:
        if target is None and existing['target_commitish'] != commit:
            raise ReleaseError('已有草稿Release指向其他提交。')
        if not existing['draft']:
            assets = {asset['name'] for asset in existing['assets'] if asset['size'] > 0 and asset['state'] == 'uploaded'}
            if target == commit and {archive.name, checksum_path.name} <= assets:
                return f'{tag}已完整发布，跳过。'
            raise ReleaseError('已公开的Release附件不完整，请人工检查。')
    if target is None:
        client.request('POST', '/git/refs', dict(ref=f'refs/tags/{tag}', sha=commit))
    release_data = dict(
        tag_name=tag, target_commitish=commit, name=f'exifmark {information["version"]}',
        body=notes, draft=True, prerelease=False,
    )
    if existing:
        release = client.request('PATCH', f'/releases/{existing["id"]}', release_data)
    else:
        release = client.request('POST', '/releases', release_data)
    for asset in release['assets']:
        client.request('DELETE', f'/releases/assets/{asset["id"]}')
    upload_url = release['upload_url'].split('{')[0]
    for path in (archive, checksum_path):
        client.request(
            'POST', upload_url + '?' + urlencode(dict(name=path.name)), path.read_bytes(),
            content_type='application/zip' if path == archive else 'text/plain',
        )
    client.request('PATCH', f'/releases/{release["id"]}', dict(draft=False, make_latest='true'))
    return f'{tag}发布完成。'


def main():
    parser = argparse.ArgumentParser(description='exifmark版本、打包与发布工具')
    subparsers = parser.add_subparsers(dest='command', required=True)
    subparsers.add_parser('prepare')
    subparsers.add_parser('metadata')
    for command in ('archive-path', 'package'):
        subparser = subparsers.add_parser(command)
        subparser.add_argument('--release', action='store_true')
    subparser = subparsers.add_parser('bump')
    subparser.add_argument('level', choices=('patch', 'minor', 'major'))
    subparser = subparsers.add_parser('ci')
    subparser.add_argument('--output', type=Path)
    subparser = subparsers.add_parser('publish')
    subparser.add_argument('archive', type=Path)
    arguments = parser.parse_args()
    if arguments.command == 'prepare':
        print(json.dumps(prepare_build(PROJECT_ROOT)))
    elif arguments.command == 'metadata':
        print(json.dumps(build_info(PROJECT_ROOT)))
    elif arguments.command == 'archive-path':
        print(archive_path(PROJECT_ROOT, arguments.release))
    elif arguments.command == 'package':
        print(package_plugin(PROJECT_ROOT, arguments.release))
    elif arguments.command == 'bump':
        version = bump_version(PROJECT_ROOT, arguments.level)
        print(f'已生成{version}的版本和更新文档。请审阅并提交，提交信息可用chore(release): {version}。')
    elif arguments.command == 'ci':
        print(json.dumps(ci_context(PROJECT_ROOT, arguments.output)))
    elif arguments.command == 'publish':
        if ci_context(PROJECT_ROOT)['release'] != 'true':
            raise ReleaseError('发布仅允许main上的版本升级push事件。')
        client = GitHubClient(os.environ.get('GITHUB_REPOSITORY', ''), os.environ.get('GITHUB_TOKEN', ''))
        print(publish_release(PROJECT_ROOT, arguments.archive.resolve(), client))


if __name__ == '__main__':
    try:
        main()
    except (ReleaseError, OSError, ValueError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f'exifmark：{error}', file=sys.stderr)
        sys.exit(1)
