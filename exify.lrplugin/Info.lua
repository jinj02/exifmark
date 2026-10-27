return {
    LrSdkVersion = 13.0,
    LrSdkMinimumVersion = 13.0,
    LrToolkitIdentifier = 'dev.exify.lightroom',
    LrPluginName = 'exify',
    LrPluginInfoProvider = 'PluginInfo.lua',
    LrExportFilterProvider = {
        title = 'exify照片卡片',
        id = 'exifyCard',
        file = 'ExportFilter.lua',
        supportsVideo = false,
    },
    VERSION = { major = 0, minor = 1, revision = 0, build = 1 },
}
