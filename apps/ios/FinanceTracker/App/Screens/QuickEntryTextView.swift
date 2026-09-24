import SwiftUI
import UIKit

/// Keep first-responder ownership in UIKit along with the keyboard accessory.
struct QuickEntryTextView: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> Editor {
        let view = Editor()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = .label
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .sentences
        view.keyboardDismissMode = .none
        view.alwaysBounceVertical = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = "Quick entry"
        return view
    }

    func updateUIView(_ view: Editor, context: Context) {
        context.coordinator.text = $text
        view.overrideUserInterfaceStyle = context.environment.colorScheme == .dark ? .dark : .light
        view.keyboardAppearance = context.environment.colorScheme == .dark ? .dark : .light
        // Preserve the selection and marked text while the user is typing.
        if view.text != text, view.markedTextRange == nil {
            view.text = text
            if !view.isFirstResponder {
                view.selectedRange = NSRange(location: text.utf16.count, length: 0)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Editor, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let lineHeight = uiView.font?.lineHeight ?? 20
        let contentHeight = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: ceil(min(max(contentHeight, lineHeight * 2), lineHeight * 7)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Editor: UITextView {
        var shouldResign: (() -> Bool)?

        override func resignFirstResponder() -> Bool {
            guard shouldResign?() != false else { return false }
            return super.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            textView.invalidateIntrinsicContentSize()
        }
    }
}
