import SwiftUI
import WebKit
import HFUTCore

@MainActor
final class LoginBrowser: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var isLoading = false
    @Published var message: String?
    @Published var canFinish = false
    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = AcademicClient.userAgent
    }

    func load() { message = nil; webView.load(URLRequest(url: AcademicClient.loginURL)) }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { isLoading = true; canFinish = false }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        if webView.url?.host == "jxglstu.hfut.edu.cn", webView.url?.path.contains("/login") == false { canFinish = true }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        isLoading = false
        if (error as NSError).code != NSURLErrorCancelled { message = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let host = url.host ?? ""
        // CAS passwords stay on the HTTPS official CAS origin. Academic service is HTTP upstream.
        let allowed = (host == "cas.hfut.edu.cn" && url.scheme == "https") ||
            (host == "jxglstu.hfut.edu.cn" && ["https", "http"].contains(url.scheme ?? "")) || url.absoluteString == "about:blank"
        if !allowed { message = "登录页面尝试打开其他站点，已停止跳转。请使用学校统一认证。" }
        decisionHandler(allowed ? .allow : .cancel)
    }

    func cookies() async -> [HTTPCookie] { await webView.configuration.websiteDataStore.httpCookieStore.allCookies() }
}

private struct LoginWebView: UIViewRepresentable {
    let browser: LoginBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct LoginView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = LoginBrowser()
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("学校统一身份认证", systemImage: "lock.shield").font(.headline)
                    Text("请在学校页面输入学号、信息门户密码及验证码。成功后点“完成登录”。应用不会保存密码。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("教务系统需要校园网或系统 VPN；WebVPN 网页会话不能直接用于同步。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial)
                if browser.isLoading { ProgressView().padding(6) }
                if let message = browser.message {
                    Text(message).font(.footnote).foregroundStyle(.red).padding()
                    Button("重新加载", action: browser.load)
                }
                LoginWebView(browser: browser)
            }
            .navigationTitle("登录聚在工大").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成登录") {
                        Task {
                            if await store.connect(cookies: browser.cookies()) {
                                dismiss()
                                await store.refresh()
                            } else {
                                browser.message = store.errorMessage ?? "无法连接教务系统，请确认校园网连接及登录状态。"
                                store.errorMessage = nil
                            }
                        }
                    }.disabled(!browser.canFinish || store.isBusy)
                }
            }
            .task { browser.load() }
        }
        .interactiveDismissDisabled(store.isBusy)
    }
}
