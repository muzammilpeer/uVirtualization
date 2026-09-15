import SwiftUI
import AppKit
import UVCore

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard LibraryModel.shared.hasActiveWork else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Virtual machines or installation are still active"
        alert.informativeText = "Stop the running VMs and finish or cancel installation before quitting."
        alert.runModal()
        return .terminateCancel
    }
}

@main
struct UVApplication: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) var delegate
    @StateObject private var library = LibraryModel.shared
    var body: some Scene {
        WindowGroup("uVirtualization") {
            LibraryView().environmentObject(library).frame(minWidth: 880, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .help) {
                Button("Reveal VM Storage") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: library.store.root.path)
                }
            }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var library: LibraryModel
    @State private var showCreate = false
    @State private var showImport = false
    @State private var deleteTarget: String?
    @State private var settingsTarget: VMConfiguration?
    @State private var cloneTarget: String?
    @State private var cloneName = ""
    var body: some View {
        NavigationSplitView {
            List(selection: $library.selection) {
                Section("VIRTUAL MACHINES") {
                    ForEach(library.machines, id: \.name) { vm in
                        HStack(spacing: 12) {
                            Image(systemName: vm.guest == "macOS" ? "desktopcomputer" : "terminal")
                                .font(.title2).foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(vm.name).font(.headline)
                                Text(vm.guest + " · " + (library.statuses[vm.name] ?? "stopped")).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 7).tag(vm.name)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationSplitViewColumnWidth(min: 230, ideal: 270)
            .safeAreaInset(edge: .bottom) {
                HStack { Image(systemName: "cpu"); Text("Apple Virtualization").font(.caption); Spacer() }
                    .foregroundStyle(.secondary).padding()
            }
        } detail: {
            if let vm = library.machines.first(where: { $0.name == library.selection }) {
                VMDetail(vm: vm, showSettings: { settingsTarget = vm }, remove: { deleteTarget = vm.name }, clone: { cloneName = vm.name + "-copy"; cloneTarget = vm.name })
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "rectangle.on.rectangle").font(.system(size: 58)).foregroundStyle(.blue)
                    Text("Your next machine starts here").font(.largeTitle.bold())
                    Text("Create a macOS or Linux VM on your Mac.\nManage resources, open a guest desktop, and keep work isolated.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Create Virtual Machine") { showCreate = true }.buttonStyle(.borderedProminent).controlSize(.large)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { library.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button { showImport = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                Button { showCreate = true } label: { Label("Create", systemImage: "plus") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !library.progress.isEmpty {
                HStack {
                    if library.busy { ProgressView().controlSize(.small) }
                    Text(library.progress).font(.callout).lineLimit(2)
                    Spacer()
                    if library.busy { Button("Cancel Installation") { library.cancelInstallation() } }
                }.padding().background(.bar)
            }
        }
        .sheet(isPresented: $showCreate) { CreateSheet().environmentObject(library) }
        .sheet(isPresented: $showImport) { ImportSheet().environmentObject(library) }
        .sheet(isPresented: Binding(get: { settingsTarget != nil }, set: { if !$0 { settingsTarget = nil } })) {
            if let vm = settingsTarget { SettingsSheet(vm: vm).environmentObject(library) }
        }
        .alert("Delete virtual machine?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) { if let name = deleteTarget { library.remove(name) }; deleteTarget = nil }
        } message: { Text("This permanently removes the selected VM and its disk.") }
        .alert("Clone Virtual Machine", isPresented: Binding(get: { cloneTarget != nil }, set: { if !$0 { cloneTarget = nil } })) {
            TextField("New name", text: $cloneName)
            Button("Cancel", role: .cancel) { cloneTarget = nil }
            Button("Clone") { if let name = cloneTarget { library.clone(name, to: cloneName) }; cloneTarget = nil }
        }
        .alert("Unable to complete operation", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .task {
            library.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                library.refresh()
            }
        }
    }
}

struct VMDetail: View {
    @EnvironmentObject var library: LibraryModel
    let vm: VMConfiguration
    let showSettings: () -> Void
    let remove: () -> Void
    let clone: () -> Void
    @State private var sharePath = ""
    @State private var writable = false
    @State private var audio = false
    @State private var clipboard = false
    var stopped: Bool { (library.statuses[vm.name] ?? "stopped") == "stopped" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.guest.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(vm.name).font(.largeTitle.bold())
                        Label(vm.state == "draft" ? "Configuration draft" : (library.statuses[vm.name] ?? "stopped").capitalized, systemImage: stopped ? "circle" : "circle.fill").foregroundStyle(stopped ? Color.secondary : Color.green)
                    }
                    Spacer()
                    Image(systemName: "desktopcomputer").font(.system(size: 60)).foregroundStyle(.blue)
                }
                HStack(spacing: 14) {
                    resource("CPU", "\(vm.cpuCount) cores", "cpu")
                    resource("Memory", "\(vm.memoryMiB / 1024) GiB", "memorychip")
                    resource("Disk", "\(vm.diskGiB) GiB", "internaldrive")
                }
                HStack {
                    Button { start() } label: { Label("Start VM", systemImage: "play.fill") }.buttonStyle(.borderedProminent).disabled(!stopped || vm.state != "ready")
                    if vm.guest == "linux" {
                        Button("Run with ISO") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = false
                            if panel.runModal() == .OK, let url = panel.url { start(iso: url) }
                        }.disabled(!stopped)
                    }
                    Button("Shut Down") { library.control(vm.name, "stop") }.disabled(stopped)
                    Button(library.statuses[vm.name] == "paused" ? "Resume" : "Pause") { library.control(vm.name, library.statuses[vm.name] == "paused" ? "resume" : "pause") }.disabled(stopped)
                    Menu("More") {
                        Button("Configure…", action: showSettings).disabled(!stopped)
                        Button("Clone…", action: clone).disabled(!stopped)
                        Button("Force Stop", role: .destructive) { library.control(vm.name, "force-stop") }.disabled(stopped)
                        Divider()
                        Button("Delete…", role: .destructive, action: remove).disabled(!stopped)
                    }
                }
                GroupBox("Guest access") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Audio output", isOn: $audio)
                        Toggle("Share clipboard", isOn: $clipboard)
                        HStack {
                            Text(sharePath.isEmpty ? "No shared folder" : sharePath).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Choose Folder") {
                                let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                                if panel.runModal() == .OK { sharePath = panel.url?.path ?? "" }
                            }
                            if !sharePath.isEmpty { Button("Remove") { sharePath = "" } }
                        }
                        if !sharePath.isEmpty { Toggle("Allow the guest to write to this folder", isOn: $writable) }
                        Text("Access settings apply the next time this VM starts. Networking uses NAT.").font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }.disabled(!stopped)
                Text("Display: \(vm.displayWidth) × \(vm.displayHeight)\nNetwork address: \(vm.macAddress ?? "Assigned at installation")").font(.callout).foregroundStyle(.secondary)
            }.padding(36)
        }
    }
    func start(iso: URL? = nil) {
        library.start(vm.name, iso: iso, share: sharePath.isEmpty ? nil : "shared=\(sharePath):\(writable ? "rw" : "ro")", audio: audio, clipboard: clipboard)
    }
    func resource(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Label(label, systemImage: icon).foregroundStyle(.secondary); Text(value).font(.title2.weight(.semibold)) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
