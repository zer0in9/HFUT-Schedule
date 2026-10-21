import Foundation

public struct CampusService: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    public let category: String
    public let address: String
    public let xuanchengAddress: String?
    public let requiresCampusNetwork: Bool
    public func url(campus: Campus) -> URL { URL(string: campus == .xuancheng ? xuanchengAddress ?? address : address)! }

    // Addresses mirror network-api/.../model/Constant.kt; services open their official site.
    public static let all: [CampusService] = [
        .init(id: "portal", title: "信息门户", symbol: "person.crop.rectangle", category: "学习", address: "https://one.hfut.edu.cn/", xuanchengAddress: nil, requiresCampusNetwork: false),
        .init(id: "academic", title: "教务系统", symbol: "graduationcap", category: "学习", address: "http://jxglstu.hfut.edu.cn/eams5-student/", xuanchengAddress: nil, requiresCampusNetwork: true),
        .init(id: "uniapp", title: "合工大教务", symbol: "book.closed", category: "学习", address: "https://jwglapp.hfut.edu.cn/uniapp/", xuanchengAddress: nil, requiresCampusNetwork: true),
        .init(id: "second", title: "第二课堂", symbol: "sparkles", category: "学习", address: "https://dekt.hfut.edu.cn/", xuanchengAddress: nil, requiresCampusNetwork: false),
        .init(id: "library", title: "图书馆", symbol: "books.vertical", category: "学习", address: "https://lib.hfut.edu.cn/", xuanchengAddress: nil, requiresCampusNetwork: false),
        .init(id: "seat", title: "座位预约", symbol: "chair", category: "学习", address: "http://210.45.242.57/", xuanchengAddress: nil, requiresCampusNetwork: true),
        .init(id: "room", title: "研讨间预约", symbol: "person.3", category: "学习", address: "http://210.45.243.31:81/", xuanchengAddress: nil, requiresCampusNetwork: true),
        .init(id: "ietp", title: "大学生创新创业", symbol: "lightbulb", category: "学习", address: "http://dcxt.hfut.edu.cn/", xuanchengAddress: nil, requiresCampusNetwork: true),
        .init(id: "unipus", title: "U 校园", symbol: "character.book.closed", category: "学习", address: "https://u.unipus.cn/", xuanchengAddress: nil, requiresCampusNetwork: false),
        .init(id: "community", title: "智慧社区", symbol: "building.2", category: "生活", address: "https://community.hfut.edu.cn/", xuanchengAddress: nil, requiresCampusNetwork: false),
        .init(id: "card", title: "校园卡", symbol: "creditcard", category: "生活", address: "https://zjgd.hfut.edu.cn:8181/", xuanchengAddress: nil, requiresCampusNetwork: false),
        .init(id: "shower", title: "呱呱淋浴", symbol: "drop", category: "生活", address: "https://bathing.hfut.edu.cn/", xuanchengAddress: nil, requiresCampusNetwork: false),
        .init(id: "repair", title: "后勤报修", symbol: "wrench.and.screwdriver", category: "生活", address: "http://zhhq.hfut.edu.cn/school/", xuanchengAddress: "http://xcfw.hfut.edu.cn/school/", requiresCampusNetwork: true),
        .init(id: "fee", title: "学费缴纳", symbol: "yensign.circle", category: "生活", address: "http://pay.hfut.edu.cn/payment/mobileOnlinePay", xuanchengAddress: nil, requiresCampusNetwork: true),
        .init(id: "fitness", title: "体测平台", symbol: "figure.run", category: "生活", address: "https://bdlp.hfut.edu.cn/bdlp_h5_fitness_test/view/main/newIndex.html", xuanchengAddress: nil, requiresCampusNetwork: true),
        .init(id: "network", title: "校园网自服务", symbol: "wifi", category: "生活", address: "https://xywzz.hfut.edu.cn:8443/", xuanchengAddress: nil, requiresCampusNetwork: true),
        .init(id: "vpn", title: "WebVPN", symbol: "network", category: "校园", address: "https://webvpn.hfut.edu.cn/", xuanchengAddress: nil, requiresCampusNetwork: false),
        .init(id: "news", title: "通知公告", symbol: "megaphone", category: "校园", address: "https://news.hfut.edu.cn/", xuanchengAddress: "https://xc.hfut.edu.cn/", requiresCampusNetwork: false),
        .init(id: "jwc", title: "教务处", symbol: "building.columns", category: "校园", address: "https://jwc.hfut.edu.cn/", xuanchengAddress: "https://xcjwb.hfut.edu.cn/", requiresCampusNetwork: false),
        .init(id: "ehall", title: "办事大厅", symbol: "rectangle.grid.2x2", category: "校园", address: "https://ehall.hfut.edu.cn/", xuanchengAddress: nil, requiresCampusNetwork: false),
        .init(id: "stu", title: "学工系统", symbol: "person.text.rectangle", category: "校园", address: "https://stu.hfut.edu.cn/", xuanchengAddress: nil, requiresCampusNetwork: false),
        .init(id: "jobs", title: "就业信息", symbol: "briefcase", category: "校园", address: "https://gdjy.hfut.edu.cn/", xuanchengAddress: "https://xcjy.hfut.edu.cn/", requiresCampusNetwork: false),
        .init(id: "alumni", title: "校友平台", symbol: "person.2", category: "校园", address: "https://xypt.hfut.edu.cn/", xuanchengAddress: nil, requiresCampusNetwork: false),
        .init(id: "school", title: "学校官网", symbol: "globe.asia.australia", category: "校园", address: "https://www.hfut.edu.cn/", xuanchengAddress: "https://xc.hfut.edu.cn/", requiresCampusNetwork: false)
    ]
}
