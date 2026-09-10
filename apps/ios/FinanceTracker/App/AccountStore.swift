import Combine
import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published var selectedAccountID: UUID?
    @Published var isManagingAccounts = false
    @Published var alertMessage: String?
    @Published private(set) var isLoading = false
    private let repository: LocalFinanceRepository
    private var isPreview = false
    private var subscription: AnyCancellable?

    init(apiClient: APIClient = APIClient(), repository: LocalFinanceRepository? = nil) {
        self.repository = repository ?? .shared
        apply(self.repository.snapshot)
        subscription = self.repository.$snapshot.sink { [weak self] in self?.apply($0) }
    }
    private func apply(_ snapshot: LocalSnapshot) {
        accounts = snapshot.sortedAccounts
        if let selectedAccountID, snapshot.accounts[selectedAccountID] == nil { self.selectedAccountID = nil }
    }
    var selectedAccount: Account? { accounts.first { $0.id == selectedAccountID } }
    var selectionTitle: String { selectedAccount?.name ?? "All Accounts" }
    func loadAccounts(force: Bool = false) async { guard !isPreview else { return }; apply(repository.snapshot) }
    @discardableResult
    func createAccount(name: String, type: AccountType, currency: String, icon: String, iconColor: AccountIconColor) async throws -> Account {
        let account = try repository.edit { try $0.saveAccount(name: name, type: type, currency: currency, icon: icon, color: iconColor) }
        selectedAccountID = account.id; return account
    }
    @discardableResult
    func updateAccount(id: UUID, name: String, type: AccountType, currency: String, icon: String, iconColor: AccountIconColor) async throws -> Account {
        try repository.edit { try $0.saveAccount(id: id, name: name, type: type, currency: currency, icon: icon, color: iconColor) }
    }
    func reorderAccounts(_ accounts: [Account]) async throws { try repository.edit { try $0.reorderAccounts(accounts) } }
    func deleteAccount(_ account: Account) async throws { try repository.edit { $0.deleteAccount(account.id) } }
#if DEBUG
    static func preview(accounts: [Account], selectedAccountID: UUID? = nil) -> AccountStore {
        let store = AccountStore(); store.subscription = nil; store.isPreview = true; store.accounts = accounts; store.selectedAccountID = selectedAccountID; return store
    }
#endif
}
