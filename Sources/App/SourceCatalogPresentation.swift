import Foundation

/// Presentation metadata only. Available sources always come from the engine catalog.
struct SourceChoice: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let symbol: String
    let category: String
    let order: Int
    let originalName: String

    init(_ source: [String: Any]) {
        id = source.string("id"); originalName = source.string("name")
        let data: (String, String, String, String, String, Int)
        switch id {
        case "dante_audio_visualizer":
            data = ("Visualizador de áudio", "Ondas e espectros que reagem ao som em tempo real.", "Escolha uma fonte de áudio da cena, um dos dez desenhos e duas cores. Redimensione livremente no canvas sem deformar o desenho.", "waveform.path", "Elementos", 10)
        case "dante_marquee":
            data = ("Faixa de texto rolante", "Avisos, links e cupons no rodapé da live.", "Uma faixa de ponta a ponta, com altura, velocidade, cores, fonte, negrito e itálico ajustáveis. Texto salvo com a cena.", "text.line.first.and.arrowtriangle.forward", "Elementos", 13)
        case "dante_qrcode":
            data = ("QR Code", "Links, texto ou Pix para sua audiência.", "Escolha o tipo nas Propriedades e gere o código localmente. Personalize cores, estilo e logo, depois posicione na cena.", "qrcode", "Elementos", 14)
        case "dante_youtube_alert":
            data = ("Likes e novos inscritos", "Likes, novos públicos e total aproximado do canal.", "Conecte o YouTube e inicie a live. Escolha entre seis estilos editáveis nas Propriedades. Inscritos públicos entram em fila; likes mostram o total do vídeo, sem identificar pessoas.", "hand.thumbsup.fill", "Elementos", 15)
        case "dante_youtube_chat":
            data = ("Chat do YouTube", "Uma janela com a conversa da sua live.", "Mostra as mensagens recentes da live conectada. Super Chats ficam na fila de revisão. Personalize estilo, cor e fonte nas Propriedades.", "bubble.left.and.bubble.right.fill", "Elementos", 11)
        case "dante_superchat":
            data = ("Destaque de comentário", "Perguntas e Super Chats aprovados por você.", "Selecione uma mensagem no painel Chat. Ela entra com animação e fica até você ocultar. O olho da fonte controla sua visibilidade na cena.", "text.bubble.fill", "Elementos", 12)
        case "macos-avcapture":
            data = ("Câmera", "Webcam, câmera USB ou iPhone compatível.", "Adicione a câmera e escolha o dispositivo e a resolução na janela de prévia. O iPhone precisa estar disponível como câmera no macOS.", "web.camera.fill", "Câmera e tela", 0)
        case "screen_capture":
            data = ("Tela ou janela", "Compartilhe um monitor, uma janela ou um app.", "Mostre uma apresentação, um aplicativo ou sua tela. Após adicionar, escolha o conteúdo no painel Propriedades e autorize a captura no macOS.", "macwindow.on.rectangle", "Câmera e tela", 1)
        case "coreaudio_input_capture":
            data = ("Microfone", "Sua voz, uma interface ou outra entrada de som.", "Escolha a entrada de áudio que deseja enviar à live. Depois, ajuste volume e mute pelo mixer.", "mic.fill", "Áudio", 2)
        case "sck_audio_capture":
            data = ("Áudio do Mac", "Som do sistema ou de um aplicativo.", "Selecione o sistema ou um aplicativo inteiro. Para separar o som de uma única aba do Chrome, use Áudio de aba do navegador.", "speaker.wave.2.fill", "Áudio", 3)
        case "dante_browser_tab_audio":
            data = ("Áudio de aba do navegador", "Som de uma aba específica do Google Chrome.", "O Chrome abre seu seletor de abas. Escolha a aba, ative Compartilhar áudio e mantenha a página de captura aberta. O som entra no mixer como uma fonte independente; outras abas ficam de fora.", "macwindow.badge.plus", "Áudio", 4)
        case let value where value.hasPrefix("image_source"):
            data = ("Imagem", "Logo, foto, arte ou sobreposição.", "Escolha um arquivo de imagem. Depois de adicionar, arraste e redimensione a imagem no canvas para compor sua cena.", "photo.fill", "Elementos", 4)
        case let value where value.hasPrefix("text_ft2_source"):
            data = ("Texto", "Títulos, legendas e chamadas na tela.", "Escreva o texto e escolha sua aparência. Use para identificar participantes, exibir títulos ou destacar uma mensagem durante a live.", "textformat", "Elementos", 5)
        case "ffmpeg_source":
            data = ("Vídeo ou áudio", "Reproduza um arquivo de mídia na live.", "Adicione um vídeo, vinheta ou arquivo de áudio. Configure repetição e reprodução nas propriedades da fonte.", "play.rectangle.fill", "Elementos", 6)
        case let value where value.hasPrefix("slideshow"):
            data = ("Slides de imagens", "Uma sequência de fotos ou artes.", "Selecione várias imagens e configure o tempo e a transição entre elas. Para mostrar slides de um aplicativo, use Tela ou janela.", "photo.stack.fill", "Elementos", 7)
        case let value where value.hasPrefix("color_source"):
            data = ("Cor de fundo", "Um fundo liso ou bloco de cor.", "Escolha a cor e o tamanho. Você pode usar como fundo da cena ou como faixa atrás de um texto.", "paintpalette.fill", "Elementos", 8)
        case "macos-avcapture-fast":
            data = ("Placa de captura", "Vídeo de uma capturadora compatível.", "Adicione uma entrada de vídeo fornecida por uma placa de captura. A disponibilidade de dispositivos e formatos depende do suporte no macOS.", "externaldrive.connected.to.line.below", "Câmera e tela", 9)
        case "display_capture":
            data = ("Monitor • legado", "Alternativa para capturar um monitor.", "Captura de compatibilidade. Prefira Tela ou janela para novas fontes; use esta alternativa se precisar do método antigo.", "display", "Compatibilidade", 20)
        case "window_capture":
            data = ("Janela • legado", "Alternativa para capturar uma janela.", "Captura de compatibilidade. Prefira Tela ou janela para novas fontes; use esta alternativa se precisar do método antigo.", "macwindow", "Compatibilidade", 21)
        case "coreaudio_output_capture":
            data = ("Saída de áudio", "Dispositivo de áudio de retorno ou virtual.", "Selecione um dispositivo de áudio compatível, como uma interface virtual instalada. Para capturar o som do sistema diretamente, use Áudio do Mac.", "hifispeaker.fill", "Áudio", 10)
        case "av_capture_input":
            data = ("Câmera • legado", "Método antigo de captura de câmera.", "Fonte de compatibilidade. Prefira Câmera para novas cenas, quando disponível.", "video.fill", "Compatibilidade", 22)
        default:
            data = (originalName, "Fonte adicional disponível neste Mac.", "Configure esta fonte com as opções fornecidas pelo módulo instalado.", "square.stack.3d.up.fill", "Outras", 30)
        }
        (title, subtitle, detail, symbol, category, order) = data
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || [title, subtitle, detail, originalName].contains { $0.localizedStandardContains(query) }
    }
}
