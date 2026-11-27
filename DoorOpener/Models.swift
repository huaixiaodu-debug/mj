import Foundation

/// 门禁设备
struct Door: Identifiable, Codable, Hashable {
    let id: Int
    let ext: Int
    let name: String
    let full: String
    let online: Bool

    /// 从内置 doors.json 解码（字段 id/ext/name/full/online）
    enum CodingKeys: String, CodingKey {
        case id, ext, name, full, online
    }
}

/// 开门命令结果
struct CommandResult: Codable {
    let commandRecvDt: String?
    let extendName: String?
    let refMsg: String?
    let cmdId: Int?
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case commandRecvDt = "COMMANDRECVDT"
        case extendName = "EXTENDNAME"
        case refMsg = "REFMSG"
        case cmdId = "CMDID"
        case fullName = "FULLNAME"
    }

    var isSuccess: Bool {
        (refMsg ?? "").contains("开门成功")
    }
}

/// 登录结果
enum LoginState: Equatable {
    case idle
    case needCaptcha
    case loggedIn
    case failed(String)
}

/// 操作结果提示
struct OpResult: Identifiable, Equatable {
    let id = UUID()
    let doorName: String
    let success: Bool
    let message: String
    let time: String
}
