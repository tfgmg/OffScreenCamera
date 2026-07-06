import SwiftUI

struct CalculatorDisguiseView: View {
    @ObservedObject var appLock: AppLockService
    let onUnlocked: () -> Void

    @State private var display = "0"
    @State private var secretInput = ""
    @State private var shake = false

    private let buttons: [[CalcKey]] = [
        [.clear, .plusMinus, .percent, .divide],
        [.digit("7"), .digit("8"), .digit("9"), .multiply],
        [.digit("4"), .digit("5"), .digit("6"), .subtract],
        [.digit("1"), .digit("2"), .digit("3"), .add],
        [.digit("0"), .decimal, .equals]
    ]

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(display)
                .font(.system(size: 64, weight: .light, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 24)
                .modifier(ShakeEffect(animatableData: shake ? 1 : 0))

            ForEach(buttons.indices, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(buttons[row], id: \.self) { key in
                        calcButton(key)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.black.ignoresSafeArea())
        .task {
            if AppSettings.shared.biometricEnabled, appLock.hasPIN {
                if await appLock.unlockWithBiometrics() {
                    onUnlocked()
                }
            }
        }
    }

    @ViewBuilder
    private func calcButton(_ key: CalcKey) -> some View {
        let isWide = key == .digit("0")

        Button {
            handleKey(key)
        } label: {
            Text(key.title)
                .font(.title2.weight(.medium))
                .foregroundStyle(key.foregroundColor)
                .frame(maxWidth: isWide ? .infinity : nil)
                .frame(width: isWide ? nil : 78, height: 78)
                .background(key.backgroundColor, in: Circle())
        }
        .frame(maxWidth: isWide ? .infinity : nil)
    }

    private func handleKey(_ key: CalcKey) {
        switch key {
        case .clear:
            display = "0"
            secretInput = ""
        case .equals:
            let pin = display.filter(\.isNumber)
            if appLock.verifyPIN(pin) {
                onUnlocked()
            } else if !pin.isEmpty {
                withAnimation { shake.toggle() }
            }
            secretInput = ""
            display = "0"
        case .digit(let value):
            secretInput += value
            display = display == "0" ? value : display + value
        default:
            secretInput += key.title
            display = key.title
        }
    }
}

private enum CalcKey: Hashable {
    case clear, plusMinus, percent, divide
    case multiply, subtract, add, equals, decimal
    case digit(String)

    var title: String {
        switch self {
        case .clear: return "AC"
        case .plusMinus: return "±"
        case .percent: return "%"
        case .divide: return "÷"
        case .multiply: return "×"
        case .subtract: return "−"
        case .add: return "+"
        case .equals: return "="
        case .decimal: return "."
        case .digit(let d): return d
        }
    }

    var backgroundColor: Color {
        switch self {
        case .clear, .plusMinus, .percent: return Color(.systemGray3)
        case .divide, .multiply, .subtract, .add, .equals: return .orange
        default: return Color(.systemGray2)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .clear, .plusMinus, .percent: return .black
        default: return .white
        }
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 10 * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
