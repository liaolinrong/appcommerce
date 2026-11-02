import CommerceCore
import SwiftUI

@MainActor
public struct CommerceStateView<Content: View>: View {
    private let controller: CommerceController
    private let content: (AccessState, Bool, Bool, CommerceError?) -> Content

    public init(
        controller: CommerceController,
        @ViewBuilder content: @escaping (AccessState, Bool, Bool, CommerceError?) -> Content
    ) {
        self.controller = controller
        self.content = content
    }

    public var body: some View {
        content(controller.accessState, controller.canEdit, controller.isBusy, controller.error)
    }
}

@MainActor
public struct CommerceStatusView: View {
    private let controller: CommerceController
    private let language: CommerceLanguage

    public init(controller: CommerceController, language: CommerceLanguage) {
        self.controller = controller
        self.language = language
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: CommerceLocalization.status(controller.accessState, language: language))
            if controller.isBusy {
                ProgressView {
                    Text(verbatim: CommerceLocalization.text(.busy, language: language))
                }
            }
            if let error = controller.error {
                Text(verbatim: CommerceLocalization.error(error, language: language))
                    .foregroundStyle(.red)
            }
        }
    }
}