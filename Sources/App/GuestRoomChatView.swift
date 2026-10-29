import SwiftUI

/// Observe the guest model directly: StudioView does not publish nested guest
/// state, so its own updates cannot drive the window's open/close binding.
struct GuestRoomChatWindowPresenter: View {
    @ObservedObject var guests: GuestModel

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .studioPanel(isPresented: $guests.chatOpen, title: "Conversa dos participantes") {
                GuestRoomChatView(guests: guests)
            }
    }
}

/// Studio-only communication. This view is outside the engine canvas and never
/// enters the program, recording, projector or guest return video.
struct GuestRoomChatView: View {
    @ObservedObject var guests: GuestModel
    @LegacyState private var draft = ""
    @LegacyState private var recipient = "all"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if guests.hostChatMessages.isEmpty {
                            Text("As mensagens da sala aparecem aqui. Escolha Todos ou @participante para enviar em privado.")
                                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        }
                        ForEach(guests.hostChatMessages) { message in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(message.senderName).font(.caption.weight(.semibold))
                                    if message.recipientID != nil {
                                        Text("Privada para @\(message.recipientName ?? "participante")")
                                            .font(.caption2).foregroundStyle(.orange)
                                    }
                                    Spacer(minLength: 0)
                                    Text(message.sentAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(10)
                            .background(message.senderID == "host" ? Color.teal.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                            .id(message.id)
                        }
                    }.padding(12)
                }
                .onChange(of: guests.hostChatMessages.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Picker("Para", selection: $recipient) {
                    Text("Todos • conversa geral").tag("all")
                    ForEach(guests.chatRecipients, id: \.id) { participant in
                        Text("@\(participant.name) • privada").tag(participant.id)
                    }
                }.labelsHidden().accessibilityLabel("Destinatário da mensagem")
                HStack {
                    TextField("Escreva para os participantes", text: $draft, axis: .vertical)
                        .lineLimit(1...3).onSubmit(send)
                        .accessibilityLabel("Mensagem para os participantes")
                    Button("Enviar", action: send).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if recipient != "all" { Text("Privada: somente você e o destinatário verão esta mensagem.").font(.caption2).foregroundStyle(.orange) }
                if let error = guests.chatError { Text(error).font(.caption2).foregroundStyle(.red) }
            }.padding(12)
        }
        .frame(width: 380, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
    }

    private func send() {
        if guests.sendHostChat(draft, to: recipient) { draft = "" }
    }
}
