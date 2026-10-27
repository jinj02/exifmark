import Darwin
import ExifmarkCore
import Foundation

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--version"] {
        print("exifmark-render 0.1.0 (request v1)")
        return
    }
    guard arguments.count == 2, ["--request", "--install-jpeg"].contains(arguments[0]) else {
        throw RenderError.invalid("用法：exifmark-render --request|--install-jpeg /absolute/path/request.json")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    if arguments[0] == "--install-jpeg" {
        try JSONDecoder().decode(JPEGInstallRequest.self, from: data).install()
        return
    }
    let request: RenderRequest
    do { request = try JSONDecoder().decode(RenderRequest.self, from: data) }
    catch { throw RenderError.invalid("无效的渲染请求：\(error.localizedDescription)") }
    let result = try autoreleasepool { try CardRenderer().render(request) }
    let output = try JSONEncoder().encode(result)
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("exifmark：\(error.localizedDescription)\n".utf8))
    exit(1)
}
