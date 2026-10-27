import Darwin
import ExifyCore
import Foundation

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--version"] {
        print("exify-render 0.1.0 (request v1)")
        return
    }
    guard arguments.count == 2, arguments[0] == "--request" else {
        throw RenderError.invalid("用法：exify-render --request /absolute/path/request.json")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
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
    FileHandle.standardError.write(Data("exify：\(error.localizedDescription)\n".utf8))
    exit(1)
}
