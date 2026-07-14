import SwiftUI

// ===========================================================
// Hero-карусель (как featured у Apple TV+) — перенос анимации
// из PWA: фон КРОССФЕЙДИТ по доле горизонтальной прокрутки,
// контент (лого/мета/кнопка) листается поверх, при вертикальном
// скролле фон отъезжает медленнее (параллакс) и растягивается
// при оттягивании вниз. Тап — zoom-переход в детальную.
// ===========================================================

struct HeroEntry: Identifiable, Hashable {
    let item: MediaItem
    let logoPath: String?
    var id: Int { item.id }
}

struct HeroRoute: Hashable {
    let type: MediaType
    let id: Int
}

struct HeroCarousel: View {
    let entries: [HeroEntry]
    let scrollY: CGFloat
    let zoomNamespace: Namespace.ID

    @State private var pagePos: CGFloat = 0

    private var height: CGFloat {
        UIScreen.main.bounds.height * 0.62
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Фон: стопка бэкдропов, кроссфейд по дробному индексу слайда.
            backgroundLayer

            // Градиент в фон приложения.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: Theme.bg.opacity(0.55), location: 0.8),
                    .init(color: Theme.bg, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Контент — горизонтальный пейджер поверх фона.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(entries) { entry in
                        slide(entry)
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.x / max(geo.containerSize.width, 1)
            } action: { _, newValue in
                pagePos = newValue
            }

            // Точки-индикатор.
            HStack(spacing: 7) {
                ForEach(0..<entries.count, id: \.self) { i in
                    Circle()
                        .fill(i == Int(round(pagePos)) ? Theme.accent : .white.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 10)
        }
        .frame(height: height)
        .clipped()
    }

    private var backgroundLayer: some View {
        ZStack {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                RemoteImage(url: TMDB.backdrop(entry.item.backdropPath, "w1280")
                                ?? TMDB.poster(entry.item.posterPath, "w780"))
                    // Ширину жёстко ограничиваем контейнером: иначе .fill-картинка
                    // выкладывается шире экрана (height*aspect) и раздувает весь стек.
                    .frame(height: height)
                    .containerRelativeFrame(.horizontal)
                    .clipped()
                    .opacity(Double(max(0, 1 - abs(CGFloat(i) - pagePos))))
            }
        }
        // Параллакс: как в вебе — фон отъезжает медленнее контента (y*0.5) и
        // слегка масштабируется; при оттягивании вниз — растягивается (stretchy).
        .offset(y: scrollY >= 0 ? scrollY * 0.5 : scrollY)
        .scaleEffect(
            scrollY >= 0
                ? 1 + min(scrollY, 800) / 4000
                : 1 + min(-scrollY, 600) / max(height, 1),
            anchor: .top
        )
    }

    private func slide(_ entry: HeroEntry) -> some View {
        NavigationLink(value: HeroRoute(type: entry.item.mediaType, id: entry.item.id)) {
            VStack(spacing: 12) {
                Spacer()

                Text("В тренде")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.35), in: .capsule)

                if let logo = entry.logoPath {
                    RemoteImage(url: TMDB.poster(logo, "w500"), contentMode: .fit)
                        .frame(maxWidth: 260, maxHeight: 110)
                        .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
                } else {
                    Text(entry.item.title)
                        .font(.system(size: 30, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 24)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                }

                HStack(spacing: 12) {
                    Text("★ \(Fmt.rating(entry.item.voteAverage))")
                    Text(Fmt.year(entry.item.releaseDate))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))

                HStack(spacing: 8) {
                    Image(systemName: "play.circle")
                    Text("Подробнее")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.bottom, 34)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: HeroRoute(type: entry.item.mediaType, id: entry.item.id), in: zoomNamespace)
    }
}
