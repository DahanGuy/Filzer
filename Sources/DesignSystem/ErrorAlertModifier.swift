import SwiftUI

/// Standard error-alert wiring used by every screen that can fail an async file
/// operation: `@State private var errorMessage: String?`, then `.errorAlert($errorMessage)`.
private struct ErrorAlertModifier: ViewModifier {
	@Binding var errorMessage: String?

	func body(content: Content) -> some View {
		content.alert("Error", isPresented: isPresented) {
			Button("OK") { errorMessage = nil }
		} message: {
			Text(errorMessage ?? "")
		}
	}

	private var isPresented: Binding<Bool> {
		Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
	}
}

extension View {
	func errorAlert(_ message: Binding<String?>) -> some View {
		modifier(ErrorAlertModifier(errorMessage: message))
	}
}
