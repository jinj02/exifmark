return {
    LrSdkVersion = 14.3,
    LrSdkMinimumVersion = 14.3,
    LrToolkitIdentifier = 'dev.exifmark.lightroom',
    LrPluginName = 'exifmark',
    LrPluginInfoProvider = 'PluginInfo.lua',
    LrExportFilterProvider = {
        title = 'exifmark照片卡片',
        id = 'exifmarkCard',
        file = 'ExportFilter.lua',
        supportsVideo = false,
    },
    VERSION = { major = 0, minor = 1, revision = 0, build = 0 },
}
