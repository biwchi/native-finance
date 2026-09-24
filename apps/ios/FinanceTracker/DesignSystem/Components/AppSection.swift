import SwiftUI

struct AppSection<Content: View, Header: View, Footer: View>: View {
    @Environment(\.usesFormLayout) private var usesFormLayout
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
        Section {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
                .listRowInsets(EdgeInsets(
                    top: usesFormLayout ? AppSpacing.large : 15,
                    leading: AppSpacing.large,
                    bottom: usesFormLayout ? AppSpacing.large : 15,
                    trailing: AppSpacing.large
                ))
        } header: {
            if Header.self != EmptyView.self {
                HStack(spacing: 0) { header.textCase(nil) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: headerTopInset,
                                             leading: AppSpacing.large,
                                             bottom: AppSpacing.small, trailing: AppSpacing.large))
            }
        } footer: {
            if Footer.self != EmptyView.self {
                footer
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: AppSpacing.small, leading: AppSpacing.large,
                                             bottom: AppSpacing.compact, trailing: AppSpacing.large))
            }
        }
        // Apply casing to the section itself so reused headers stay unchanged.
        .textCase(nil)
    }

    private var headerTopInset: CGFloat {
        // Older non-form lists add eight points around headers themselves.
        // Account for that here so the visible gap matches the iOS 26 reference.
        if #available(iOS 26.0, *) { return AppSpacing.medium }
        return usesFormLayout ? AppSpacing.medium : AppSpacing.extraSmall
    }
}
