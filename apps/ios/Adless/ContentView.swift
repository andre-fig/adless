import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var whitelistEntry: String = ""

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Status")) {
                    HStack {
                        Text("VPN")
                        Spacer()
                        Text(viewModel.statusText)
                            .foregroundStyle(viewModel.isOn ? .green : .secondary)
                    }
                    HStack {
                        Text("Domínios bloqueados")
                        Spacer()
                        Text("\(viewModel.blockedCount)")
                            .monospacedDigit()
                    }
                    Toggle(isOn: Binding(get: { viewModel.isOn }, set: { _ in Task { await viewModel.toggle() } })) {
                        Text(viewModel.isOn ? "Desativar" : "Ativar")
                    }
                    .disabled(viewModel.isUpdating)
                }

                Section(header: Text("Blocklists"), footer: footerText) {
                    if viewModel.availableSources.isEmpty {
                        Text("Nenhuma lista configurada")
                    } else {
                        ForEach($viewModel.availableSources) { $source in
                            Toggle(isOn: $source.isEnabled) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.name)
                                    Text(source.url.absoluteString)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button(action: { Task { await viewModel.updateBlocklists() } }) {
                        if viewModel.isUpdating {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Text("Atualizar blocklists")
                        }
                    }
                    .disabled(viewModel.isUpdating)
                }

                Section(header: Text("Whitelist")) {
                    HStack {
                        TextField("ex: example.com", text: $whitelistEntry)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Adicionar") {
                            guard !whitelistEntry.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            viewModel.addWhitelist(domain: whitelistEntry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                            whitelistEntry = ""
                        }
                    }
                    ForEach(Array(viewModel.whitelist.enumerated()), id: \.offset) { index, domain in
                        Text(domain)
                    }
                    .onDelete(perform: viewModel.removeWhitelist)
                }

                Section(header: Text("Notas")) {
                    Label("Nenhum dado sai do dispositivo", systemImage: "lock.shield")
                    Label("DNS via proxy local, sem mudar IP", systemImage: "network")
                    Label("Sem analytics ou login", systemImage: "nosign")
                }
            }
            .navigationTitle("Adless")
        }
    }

    private var footerText: some View {
        Text("As listas são aplicadas localmente e respostas bloqueadas retornam 0.0.0.0. Upstream: 1.1.1.1/8.8.8.8.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: AppViewModel())
    }
}
