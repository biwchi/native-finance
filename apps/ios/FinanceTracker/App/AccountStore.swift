import Combine
import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published var selectedAccountID: UUID?
    @Published var isManagingAccounts = false
    @Published var alertMessage: String?
    @Published private(set) var isLoading = false

    private let apiClient: APIClient
    private var hasLoaded = false

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

#if DEBUG
    static func preview(
        accounts: [Account],
        selectedAccountID: UUID? = nil
    ) -> AccountStore {
        let store = AccountStore()
        store.accounts = accounts
        store.selectedAccountID = selectedAccountID
        store.hasLoaded = true
        return store
    }
#endif

    var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountID }
    }

    var selectionTitle: String {
        selectedAccount?.name ?? "All Accounts"
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

        return account
    }

    func reorderAccounts(_ reorderedAccounts: [Account]) async throws {
        let currentIDs = Set(accounts.map(\.id))
        let reorderedIDs = reorderedAccounts.map(\.id)
        guard reorderedAccounts.count == accounts.count,
              Set(reorderedIDs) == currentIDs else {
            return
        }

        let previousAccounts = accounts
        accounts = reorderedAccounts

        do {
            accounts = try await apiClient.reorderAccounts(reorderedIDs)
        } catch {
            accounts = previousAccounts
            throw error
        }
    }

    func deleteAccount(_ account: Account) async throws {
        _ = try await apiClient.deleteAccount(id: account.id)
        accounts.removeAll { $0.id == account.id }

        if selectedAccountID == account.id {
            selectedAccountID = nil
        }
    }
}
