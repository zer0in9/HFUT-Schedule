import SwiftUI
import ScheduleShared

@main
struct HFUTScheduleApp: App {
    var body: some Scene {
        WindowGroup {
            SharedScheduleView()
                .ignoresSafeArea() // Compose owns safe drawing / keyboard insets.
        }
    }
}

private struct SharedScheduleView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        MainViewControllerKt.MainViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
