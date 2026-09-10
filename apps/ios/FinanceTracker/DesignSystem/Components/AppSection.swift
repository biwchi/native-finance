import SwiftUI

struct AppSection<Content: View, Header: View, Footer: View>: View {
    @Environment(\.usesLegacyFormLayout) private var usesLegacyFormLayout
    private let content: Content
    private let header: Header
    private let footer: Footer

    init(@ViewBuilder content: () -> Content,
         @ViewBuilder header: () -> Header,
         @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    init(@ViewBuilder content: () -> Content) where Header == EmptyView, Footer == EmptyView {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }

    init(_ title: String, @ViewBuilder content: () -> Content) where Header == Text, Footer == EmptyView {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) where Footer == EmptyView {
        self.init(content: content, header: header, footer: { EmptyView() })
    }

    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) where Header == EmptyView {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            section
        } else {
            // Older lists reapply uppercase during reuse unless it is disabled on the section.
            section.textCase(nil)
        }
    }

    private var section: some View {
        Section {
            content.legacyListRows(verticalPadding: usesLegacyFormLayout ? AppSpacing.large : 15)
        } header: {
            if #available(iOS 26.0, *) {
                header
            } else if Header.self != EmptyView.self {
                HStack(spacing: 0) { header.textCase(nil) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.body.weight(.semibold))
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: usesLegacyFormLayout ? AppSpacing.medium : AppSpacing.extraSmall,
                                             leading: AppSpacing.large,
                                             bottom: AppSpacing.small, trailing: AppSpacing.large))
            }
        } footer: {
            if #available(iOS 26.0, *) {
                footer
            } else {
                footer
                    .listRowInsets(EdgeInsets(top: AppSpacing.small, leading: AppSpacing.large,
                                             bottom: AppSpacing.compact, trailing: AppSpacing.large))
            }
        }
    }
}
