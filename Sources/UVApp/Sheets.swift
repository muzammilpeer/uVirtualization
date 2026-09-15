import SwiftUI
import UVCore
import AppKit

struct CreateSheet: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var linux = false
    @State private var ipsw = "latest"
    @State private var cpu = 4
    @State private var memory = 4096
    @State private var disk = 64
    var valid: Bool { (try? VMConfiguration(name: name, cpuCount: cpu, memoryMiB: memory, diskGiB: disk)) != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Create Virtual Machine").font(.title.bold())
            Text("A separate workspace, powered by your Mac.").foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $name)
                Picker("Operating system", selection: $linux) { Text("macOS").tag(false); Text("Linux ARM64").tag(true) }
                if !linux {
                    HStack {
                        TextField("Restore image", text: $ipsw)
                        Button("Choose IPSW") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = false
                            if panel.runModal() == .OK { ipsw = panel.url?.path ?? "latest" }
                        }
                    }
                    Text("Use “latest” to download Apple's compatible restore image.").font(.caption).foregroundStyle(.secondary)
                }
                Stepper("CPU: \(cpu) cores", value: $cpu, in: 1...ProcessInfo.processInfo.processorCount)
                Stepper("Memory: \(memory) MiB", value: $memory, in: 4096...65536, step: 1024)
                Stepper("Disk: \(disk) GiB", value: $disk, in: 20...1024, step: 4)
            }
            Text(linux ? "After creation, choose Run with ISO and select an ARM64 Linux installer." : "Installation can take several minutes and requires space for the restore image and guest disk.")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Create") { library.create(name: name, linux: linux, ipsw: ipsw, cpu: cpu, memory: memory, disk: disk); dismiss() }.buttonStyle(.borderedProminent).disabled(!valid || library.busy) }
        }.padding(28).frame(width: 530)
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    let vm: VMConfiguration
    @State var cpu: Int
    @State var memory: Int
    @State var disk: Int
    @State var width: Int
    @State var height: Int
    init(vm: VMConfiguration) {
        self.vm = vm
        _cpu = State(initialValue: vm.cpuCount); _memory = State(initialValue: vm.memoryMiB)
        _disk = State(initialValue: vm.diskGiB); _width = State(initialValue: vm.displayWidth); _height = State(initialValue: vm.displayHeight)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configure \(vm.name)").font(.title2.bold())
            Form {
                TextField("CPU cores", value: $cpu, format: .number)
                TextField("Memory (MiB)", value: $memory, format: .number)
                TextField("Disk (GiB)", value: $disk, format: .number)
                TextField("Display width", value: $width, format: .number)
                TextField("Display height", value: $height, format: .number)
            }
            Text("Disk growth also requires expanding the filesystem inside the guest.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { library.configure(vm.name, cpu: cpu, memory: memory, disk: disk, width: width, height: height); dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 440)
    }
}

struct ImportSheet: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var archive: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Import Virtual Machine").font(.title2.bold())
            TextField("New VM name", text: $name)
            HStack {
                Text(archive?.lastPathComponent ?? "Choose a .uvma archive").lineLimit(1)
                Spacer()
                Button("Choose File") { let panel = NSOpenPanel(); if panel.runModal() == .OK { archive = panel.url } }
            }
            Text("Checksums are verified and a fresh machine identity is assigned.").foregroundStyle(.secondary)
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button("Import") { if let archive { library.importArchive(archive, name: name); dismiss() } }
                    .buttonStyle(.borderedProminent).disabled(archive == nil || (try? VMConfiguration(name: name)) == nil || library.busy)
            }
        }.padding(28).frame(width: 480)
    }
}
