import Combine
import Foundation

@MainActor
final class AccountStore: ObservableObject {
    enum Editor: Identifiable {
        case add
        case edit(Account)

        var id: String {
            switch self {
            case .add: "add"
            case let .edit(account): account.id.uuidString
            }
        }

        var account: Account? {
            if case let .edit(account) = self {
                account
            } else {
                nil
            }
        }
    }

    @Published private(set) var accounts: [Account] = []
    @Published var selectedAccountID: UUID?
    @Published var editor: Editor?
    @Published var alertMessage: String?
    @Published private(set) var isLoading = false

    private let apiClient: APIClient
    private var hasLoaded = false

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountID }
    }

    var selectionTitle: String {
        selectedAccount?.name ?? "Total"
    }

    func loadAccounts(force: Bool = false) async {
        guard force || !hasLoaded else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            accounts = try await apiClient.accounts()
            hasLoaded = true

            if let selectedAccountID,
               !accounts.contains(where: { $0.id == selectedAccountID }) {
                self.selectedAccountID = nil
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createAccount(
        name: String,
        type: AccountType,
        currency: String,
        icon: String,
        iconColor: AccountIconColor
    ) async throws -> Account {
        let account = try await apiClient.createAccount(
            AccountRequest(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                currency: currency.uppercased(),
                icon: icon,
                iconColor: iconColor
            )
        )

        accounts.append(account)
        accounts.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        selectedAccountID = account.id
        hasLoaded = true

        return account
    }

    @discardableResult
    func updateAccount(
        id: UUID,
        name: String,
        type: AccountType,
        currency: String,
        icon: String,
        iconColor: AccountIconColor
    ) async throws -> Account {
        let account = try await apiClient.updateAccount(
            id: id,
            with: AccountRequest(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                currency: currency.uppercased(),
                icon: icon,
                iconColor: iconColor
            )
        )

        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        }
        accounts.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return account
    }
}
