import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: PenteGameViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button("New Game") {
                    game.newGame()
                }
                .fixedSize(horizontal: true, vertical: false)

                Button("Save") {
                    _ = game.saveGameToDisk()
                }
                .fixedSize(horizontal: true, vertical: false)

                Button("Load") {
                    _ = game.loadGameFromDisk()
                }
                .fixedSize(horizontal: true, vertical: false)

                Button("Undo") {
                    game.undoMove()
                }
                .disabled(game.moveHistory.isEmpty || game.isAIThinking)
                .fixedSize(horizontal: true, vertical: false)

                Button(game.aiPaused ? "Resume AI" : "Pause AI") {
                    game.toggleAIPause()
                }
                .disabled(game.gameOver)
                .fixedSize(horizontal: true, vertical: false)

                if game.isAIThinking {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("AI thinking...")
                    }
                }
            }

            HStack(spacing: 18) {
                Picker("Black", selection: $game.blackPlayer) {
                    ForEach(PlayerType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .frame(width: 140)

                Picker("White", selection: $game.whitePlayer) {
                    ForEach(PlayerType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .frame(width: 140)

                Picker("AI Strength", selection: $game.aiStrength) {
                    ForEach(AIStrength.allCases) { strength in
                        Text(strength.rawValue).tag(strength)
                    }
                }
                .frame(width: 160)

                Toggle("Tournament Opening", isOn: $game.tournamentOpening)
                    .toggleStyle(.switch)
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 24) {
                Label("Black captures: \(game.capturesByBlack)/5", systemImage: "circle.fill")
                    .foregroundStyle(.primary)
                Label("White captures: \(game.capturesByWhite)/5", systemImage: "circle")
                    .foregroundStyle(.primary)
                Text(game.gameOver ? "Game over" : "\(game.currentPlayer.name)'s turn")
                    .fontWeight(.semibold)
            }

            Text(game.statusMessage)
                .font(.headline)
                .foregroundStyle(game.gameOver ? .green : .primary)

            HStack(alignment: .top, spacing: 16) {
                GroupBox("Moves") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(game.moveHistory) { move in
                                Text(historyText(move))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 260)
                    .frame(maxHeight: .infinity)
                }

                PenteBoardView(
                    board: game.board,
                    lastMoveRow: game.lastMoveRow,
                    lastMoveCol: game.lastMoveCol
                ) { row, col in
                    game.playHuman(row: row, col: col)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
    }

    private func historyText(_ move: MoveRecord) -> String {
        var text = "\(move.number). \(move.player.name) \(game.coordinateLabel(row: move.row, col: move.col))"
        if !move.captured.isEmpty {
            text += " captures \(move.captured.count)"
        }
        if let result = move.result {
            text += " - \(result)"
        }
        return text
    }
}

private struct PenteBoardView: View {
    let board: [[Stone]]
    var lastMoveRow: Int?
    var lastMoveCol: Int?
    var onTap: (Int, Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let boardSize = board.count
            let margin = max(24.0, size * 0.055)
            let step = (size - (margin * 2)) / CGFloat(boardSize - 1)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.90, green: 0.72, blue: 0.42))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.black.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(radius: 2)

                Path { path in
                    for index in 0..<boardSize {
                        let x = margin + CGFloat(index) * step
                        path.move(to: CGPoint(x: x, y: margin))
                        path.addLine(to: CGPoint(x: x, y: size - margin))

                        let y = margin + CGFloat(index) * step
                        path.move(to: CGPoint(x: margin, y: y))
                        path.addLine(to: CGPoint(x: size - margin, y: y))
                    }
                }
                .stroke(.black.opacity(0.78), lineWidth: 1)

                ForEach(starPoints(boardSize), id: \.self) { point in
                    Circle()
                        .fill(.black.opacity(0.75))
                        .frame(width: step * 0.18, height: step * 0.18)
                        .position(
                            x: margin + CGFloat(point.col) * step,
                            y: margin + CGFloat(point.row) * step
                        )
                }

                ForEach(0..<boardSize, id: \.self) { row in
                    ForEach(0..<boardSize, id: \.self) { col in
                        if board[row][col] != .empty {
                            Circle()
                                .fill(board[row][col] == .black ? .black : .white)
                                .overlay {
                                    ZStack {
                                        Circle().stroke(.black.opacity(0.28), lineWidth: 1)
                                        if row == lastMoveRow, col == lastMoveCol {
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: step * 0.20, height: step * 0.20)
                                        }
                                    }
                                }
                                .frame(width: step * 0.82, height: step * 0.82)
                                .position(
                                    x: margin + CGFloat(col) * step,
                                    y: margin + CGFloat(row) * step
                                )
                                .shadow(radius: board[row][col] == .black ? 2 : 1)
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let row = Int(round((value.location.y - margin) / step))
                        let col = Int(round((value.location.x - margin) / step))
                        guard row >= 0, row < boardSize, col >= 0, col < boardSize else { return }
                        onTap(row, col)
                    }
            )
        }
    }

    private func starPoints(_ size: Int) -> [BoardPoint] {
        guard size == 19 else { return [] }
        let lines = [3, 9, 15]
        return lines.flatMap { row in lines.map { col in BoardPoint(row: row, col: col) } }
    }
}
