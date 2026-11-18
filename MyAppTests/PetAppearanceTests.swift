import Foundation
import Testing
@testable import MyApp

@Suite("Formas do bichinho")
struct PetAppearanceTests {
    @Test("O ovo é desenhado à parte e não tem forma de criatura")
    func eggHasNoCreatureForm() {
        #expect(PetStage.egg.appearance == nil)
    }

    @Test("O ovo tem espinhos")
    func eggHasSpikes() {
        #expect(EggDesign.spikes.count == 7)
        #expect(Set(EggDesign.spikes).count == EggDesign.spikes.count)
    }

    @Test("Os espinhos do ovo são simétricos")
    func eggSpikesAreSymmetric() {
        for spike in EggDesign.spikes {
            let mirrored = EggSpike(angle: -spike.angle, length: spike.length)
            #expect(EggDesign.spikes.contains(mirrored), "Falta o espelho do espinho em \(spike.angle)°")
        }
    }

    @Test("Nenhum espinho embaixo do ovo, onde ele se apoia")
    func noSpikesOnTheBottom() {
        #expect(EggDesign.spikes.allSatisfy { abs($0.angle) <= EggDesign.maxSpikeAngle })
    }

    @Test("Espinhos têm tamanho de enfeite, sem dominar o ovo")
    func spikeLengths() {
        #expect(EggDesign.spikes.allSatisfy { $0.length > 0.05 && $0.length <= 0.15 })
    }

    @Test("O Filhote mantém a forma original, uma bolinha sem partes extras")
    func babyKeepsOriginalForm() throws {
        let baby = try #require(PetStage.baby.appearance)
        #expect(baby.bodyWidth == 0.78)
        #expect(baby.bodyHeight == 0.7)
        #expect(baby.cornerRatio == 0.36)
        #expect(baby.featureCount == 0)
    }

    @Test("Cada estágio tem uma forma diferente")
    func everyStageIsUnique() {
        let forms = PetStage.allCases.compactMap(\.appearance)
        #expect(forms.count == 4)
        #expect(Set(forms).count == forms.count)
    }

    @Test("Cada evolução ganha mais partes que a anterior")
    func featuresGrowWithEvolution() {
        let counts = [PetStage.baby, .young, .adult, .legend].compactMap { $0.appearance?.featureCount }
        #expect(counts == counts.sorted())
        #expect(Set(counts).count == counts.count)
    }

    @Test("Jovem: orelhinhas, bracinhos e broto")
    func youngForm() throws {
        let young = try #require(PetStage.young.appearance)
        #expect(young.ears == .pointy)
        #expect(young.hasArms)
        #expect(young.headAccessory == .leaf)
        #expect(!young.hasTail)
        #expect(!young.hasWings)
    }

    @Test("Adulto: orelhas longas, rabinho e escudo da reserva completa")
    func adultForm() throws {
        let adult = try #require(PetStage.adult.appearance)
        #expect(adult.ears == .long)
        #expect(adult.hasTail)
        #expect(adult.bellyEmblem == "shield.fill")
        #expect(!adult.hasWings)
    }

    @Test("Lendário: asas, aura, coroa e estrela")
    func legendForm() throws {
        let legend = try #require(PetStage.legend.appearance)
        #expect(legend.hasWings)
        #expect(legend.hasAura)
        #expect(legend.headAccessory == .crown)
        #expect(legend.bellyEmblem == "star.fill")
    }

    @Test("O corpo fica mais alto conforme evolui")
    func bodyGrowsTaller() {
        let heights = [PetStage.baby, .young, .adult, .legend].compactMap { $0.appearance?.bodyHeight }
        #expect(heights == heights.sorted())
    }
}
