import SwiftUI

/// Studio-only communication. This view is outside the engine canvas and never
/// enters the program, recording, projector or guest return video.
struct GuestRoomChatView: View {
    @ObservedObject var guests: GuestModel
    @Binding var offset: CGSize
    let containerSize: CGSize
    @LegacyState private var draft = ""
    @LegacyState private var recipient = "all"
    @GestureState private var dragTranslation = CGSize.zero

    private let panelSize = CGSize(width: 380, height: 465)
    private let edgeInset: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conversa dos participantes").font(.headline)
                        Text("Só no estúdio e nos convites").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3)
                    .updating($dragTranslation) { value, state, _ in state = value.translation }
                    .onEnded { value in offset = constrained(translated(by: value.translation)) })
                .help("Arraste para mover a conversa")
                Button { guests.chatOpen = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Fechar conversa")
            }.padding(14)
            Divider()
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
        .frame(width: 380, height: 465)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.teal.opacity(0.45)))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .offset(constrained(translated(by: dragTranslation)))
        .onAppear { offset = constrained(offset) }
        .onChange(of: containerSize) { _, _ in offset = constrained(offset) }
        .accessibilityElement(children: .contain)
    }

    private func translated(by translation: CGSize) -> CGSize {
        CGSize(width: offset.width + translation.width, height: offset.height + translation.height)
    }

    private func constrained(_ proposed: CGSize) -> CGSize {
        CGSize(
            width: min(edgeInset, max(-max(0, containerSize.width - panelSize.width - edgeInset), proposed.width)),
            height: min(edgeInset, max(-max(0, containerSize.height - panelSize.height - edgeInset), proposed.height))
        )
    }

    private func send() {
        if guests.sendHostChat(draft, to: recipient) { draft = "" }
    }
}
