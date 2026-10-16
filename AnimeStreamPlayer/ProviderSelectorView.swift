import SwiftUI

// MARK: - Provider selector view (from ShikiApp's player UI)
struct ProviderSelectorView: View {
    @Binding var selectedProvider: VideoProvider?
    let providers: [VideoProvider]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(providers) { provider in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedProvider = provider
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                                .font(.largeTitle)
                            
                            Text(provider.rawValue)
                                .font(.caption)
                        }
                        .padding(8)
                        .background(selectedProvider == provider ? Color.blue : Color.gray.opacity(0.2))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
}

// MARK: - Voice selector view (from ShikiApp's voice selector UI)
struct VoiceSelectorView<ProviderContent: View>: View {
    @Binding var selectedVoiceId: Int?
    let voices: [VideoVoice]
    
    init(_ voices: [VideoVoice], _ content: ProviderContent) {
        self._voices = .constant(voices)
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(voices) { voice in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedVoiceId = voice.id
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(voice.title)
                                .fontWeight(.medium)
                            
                            Text("Эпизодов: \(voice.episodesCount)")
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        if voice.hasDubbers {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(.green)
                        }
                        
                        if voice.hasSubtitles {
                            Image(systemName: "text.quote")
                                .foregroundStyle(.purple)
                        }
                    }
                    .padding(8)
                    .background(selectedVoiceId == voice.id ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
    }
}

// MARK: - Player with provider + voice selector (from ShikiApp's player UI pattern)
struct AnimePlayerView: View {
    @State private var selectedProvider = VideoProvider.KODIK
    @State private var selectedVoiceId: Int? = 0
    let animeTitle: String
    let videoSources: [VideoSourceData]
    
    // Current voice for the selected provider
    private var currentVoice: VideoVoice? {
        guard let id = selectedVoiceId else { return nil }
        return videoSources.first(where: { $0.type == selectedProvider })?.voices[id]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Provider selector bar (from ShikiApp's top-level selector)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(videoSources.map(\.type)) { provider in
                        Button(action: {
                            selectedProvider = provider
                        }) {
                            Text(provider.rawValue)
                                .font(.caption)
                                .fontWeight(selectedProvider == provider ? .bold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedProvider == provider ? Color.blue : Color.gray.opacity(0.3))
                                .cornerRadius(8)
                        }
                    }
                }
            }
            
            // Voice selector for the selected provider
            if let current = videoSources.first(where: { $0.type == selectedProvider }), !current.voices.isEmpty {
                
                Picker("Голос", selection: $selectedVoiceId) {
                    ForEach(current.voices.indices, id: \.self) { index in
                        Text(current.voices[index].title)
                            .tag(index as Int?)
                    }
                }
                .pickerStyle(.wheel)
            }
            
            // Episode list with links (from ShikiApp's episode pattern)
            if let link = currentVoice?.episodes.first?.link {
                Link(destination: link) {
                    Text("Смотреть эпизод \(currentVoice!.episodes.first?.number ?? 1)")
                        .font(.body)
                }
                .padding()
            }
        }
        .padding(16)
    }
}
