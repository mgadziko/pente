import Foundation

enum Stone: String, Codable {
    case empty
    case black
    case white

    var opposite: Stone {
        switch self {
        case .black: return .white
        case .white: return .black
        case .empty: return .empty
        }
    }

    var name: String {
        switch self {
        case .black: return "Black"
        case .white: return "White"
        case .empty: return "Empty"
        }
    }
}

enum PlayerType: String, CaseIterable, Identifiable, Codable {
    case human = "Human"
    case ai = "AI"

    var id: String { rawValue }
}

enum AIStrength: String, CaseIterable, Identifiable, Codable {
    case fast = "Fast"
    case normal = "Normal"
    case strong = "Strong"

    var id: String { rawValue }

    var candidateLimit: Int {
        switch self {
        case .fast: return 28
        case .normal: return 72
        case .strong: return 140
        }
    }
}

struct MoveRecord: Codable, Identifiable {
    let id: UUID
    let number: Int
    let player: Stone
    let row: Int
    let col: Int
    let captured: [BoardPoint]
    let result: String?
}

struct BoardPoint: Codable, Hashable {
    let row: Int
    let col: Int
}

private struct PenteSnapshot: Codable {
    var board: [[Stone]]
    var currentPlayer: Stone
    var blackPlayer: PlayerType
    var whitePlayer: PlayerType
    var aiStrength: AIStrength
    var tournamentOpening: Bool
    var capturesByBlack: Int
    var capturesByWhite: Int
    var moveHistory: [MoveRecord]
    var gameOver: Bool
    var winner: Stone?
    var statusMessage: String
    var lastMoveRow: Int?
    var lastMoveCol: Int?
}

final class PenteGameViewModel: ObservableObject {
    let boardSize = 19
    private let winCapturePairs = 5
    private let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
    private var aiComputationToken = 0
    private var isRestoringFromLoad = false

    @Published var board: [[Stone]]
    @Published var currentPlayer: Stone = .black
    @Published var blackPlayer: PlayerType = .human {
        didSet {
            guard !isRestoringFromLoad else { return }
            saveGameToDisk(manual: false)
            scheduleAIMoveIfNeeded()
        }
    }
    @Published var whitePlayer: PlayerType = .ai {
        didSet {
            guard !isRestoringFromLoad else { return }
            saveGameToDisk(manual: false)
            scheduleAIMoveIfNeeded()
        }
    }
    @Published var aiStrength: AIStrength = .normal {
        didSet {
            guard !isRestoringFromLoad else { return }
            saveGameToDisk(manual: false)
            scheduleAIMoveIfNeeded()
        }
    }
    @Published var tournamentOpening: Bool = true {
        didSet {
            guard !isRestoringFromLoad else { return }
            newGame()
        }
    }
    @Published var capturesByBlack = 0
    @Published var capturesByWhite = 0
    @Published var moveHistory: [MoveRecord] = []
    @Published var gameOver = false
    @Published var winner: Stone?
    @Published var statusMessage = "Black to move"
    @Published var lastMoveRow: Int?
    @Published var lastMoveCol: Int?
    @Published private(set) var isAIThinking = false

    init() {
        board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize)
        if !loadGameFromDisk(manual: false) {
            newGame()
        }
    }

    func newGame() {
        aiComputationToken += 1
        board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize)
        currentPlayer = .black
        capturesByBlack = 0
        capturesByWhite = 0
        moveHistory = []
        gameOver = false
        winner = nil
        lastMoveRow = nil
        lastMoveCol = nil
        isAIThinking = false
        statusMessage = "Black to move"
        saveGameToDisk(manual: false)
        scheduleAIMoveIfNeeded()
    }

    func playHuman(row: Int, col: Int) {
        guard isHumanTurn() else { return }
        playMove(row: row, col: col)
    }

    func undoMove() {
        guard !moveHistory.isEmpty else { return }
        aiComputationToken += 1
        isAIThinking = false
        rebuildGame(through: moveHistory.count - 1)
        if !isHumanTurn(), !gameOver {
            scheduleAIMoveIfNeeded()
        }
    }

    func isHumanTurn() -> Bool {
        playerType(for: currentPlayer) == .human && !gameOver
    }

    func playerType(for stone: Stone) -> PlayerType {
        stone == .black ? blackPlayer : whitePlayer
    }

    @discardableResult
    func saveGameToDisk(manual: Bool = true) -> Bool {
        let snapshot = PenteSnapshot(
            board: board,
            currentPlayer: currentPlayer,
            blackPlayer: blackPlayer,
            whitePlayer: whitePlayer,
            aiStrength: aiStrength,
            tournamentOpening: tournamentOpening,
            capturesByBlack: capturesByBlack,
            capturesByWhite: capturesByWhite,
            moveHistory: moveHistory,
            gameOver: gameOver,
            winner: winner,
            statusMessage: statusMessage,
            lastMoveRow: lastMoveRow,
            lastMoveCol: lastMoveCol
        )

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: saveURL(), options: .atomic)
            if manual { statusMessage = "Game saved" }
            return true
        } catch {
            if manual { statusMessage = "Save failed: \(error.localizedDescription)" }
            return false
        }
    }

    @discardableResult
    func loadGameFromDisk(manual: Bool = true) -> Bool {
        do {
            let data = try Data(contentsOf: saveURL())
            let snapshot = try JSONDecoder().decode(PenteSnapshot.self, from: data)
            isRestoringFromLoad = true
            board = snapshot.board
            currentPlayer = snapshot.currentPlayer
            blackPlayer = snapshot.blackPlayer
            whitePlayer = snapshot.whitePlayer
            aiStrength = snapshot.aiStrength
            tournamentOpening = snapshot.tournamentOpening
            capturesByBlack = snapshot.capturesByBlack
            capturesByWhite = snapshot.capturesByWhite
            moveHistory = snapshot.moveHistory
            gameOver = snapshot.gameOver
            winner = snapshot.winner
            statusMessage = manual ? "Game loaded" : snapshot.statusMessage
            lastMoveRow = snapshot.lastMoveRow
            lastMoveCol = snapshot.lastMoveCol
            isRestoringFromLoad = false
            if !manual {
                scheduleAIMoveIfNeeded()
            }
            return true
        } catch {
            isRestoringFromLoad = false
            if manual { statusMessage = "Load failed: no saved game found" }
            return false
        }
    }

    func coordinateLabel(row: Int, col: Int) -> String {
        let letters = Array("ABCDEFGHJKLMNOPQRST")
        let letter = col < letters.count ? String(letters[col]) : "\(col + 1)"
        return "\(letter)\(boardSize - row)"
    }

    private func playMove(row: Int, col: Int) {
        guard isOnBoard(row, col), board[row][col] == .empty, !gameOver else { return }
        guard openingRuleAllows(row: row, col: col, player: currentPlayer) else {
            statusMessage = openingRestrictionMessage()
            return
        }

        let player = currentPlayer
        board[row][col] = player
        let captured = removeCapturedPairs(fromRow: row, col: col, player: player)
        if player == .black {
            capturesByBlack += captured.count / 2
        } else {
            capturesByWhite += captured.count / 2
        }

        lastMoveRow = row
        lastMoveCol = col

        let winningLine = hasFiveInRow(fromRow: row, col: col, player: player)
        let winningCaptures = capturePairs(for: player) >= winCapturePairs
        var result: String?
        if winningLine || winningCaptures {
            gameOver = true
            winner = player
            result = winningLine ? "wins by five in a row" : "wins by capture"
            statusMessage = "\(player.name) \(result!)"
        } else {
            currentPlayer = player.opposite
            statusMessage = "\(currentPlayer.name) to move"
        }

        moveHistory.append(MoveRecord(
            id: UUID(),
            number: moveHistory.count + 1,
            player: player,
            row: row,
            col: col,
            captured: captured,
            result: result
        ))
        saveGameToDisk(manual: false)
        scheduleAIMoveIfNeeded()
    }

    private func scheduleAIMoveIfNeeded() {
        guard !gameOver, playerType(for: currentPlayer) == .ai else { return }
        aiComputationToken += 1
        let token = aiComputationToken
        let player = currentPlayer
        isAIThinking = true
        statusMessage = "\(player.name) AI thinking..."

        let boardCopy = board
        let capturesBlack = capturesByBlack
        let capturesWhite = capturesByWhite
        let historyCount = moveHistory.count
        let openingEnabled = tournamentOpening
        let strength = aiStrength

        DispatchQueue.global(qos: .userInitiated).async {
            let move = Self.bestMove(
                for: player,
                board: boardCopy,
                capturesBlack: capturesBlack,
                capturesWhite: capturesWhite,
                historyCount: historyCount,
                tournamentOpening: openingEnabled,
                strength: strength
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                guard token == self.aiComputationToken else { return }
                self.isAIThinking = false
                if let move {
                    self.playMove(row: move.0, col: move.1)
                } else {
                    self.gameOver = true
                    self.statusMessage = "Draw: no legal moves"
                }
            }
        }
    }

    private func openingRuleAllows(row: Int, col: Int, player: Stone) -> Bool {
        guard tournamentOpening else { return true }
        let center = boardSize / 2
        if moveHistory.isEmpty {
            return player == .black && row == center && col == center
        }
        if moveHistory.count == 2, player == .black {
            return abs(row - center) >= 3 || abs(col - center) >= 3
        }
        return true
    }

    private func openingRestrictionMessage() -> String {
        if moveHistory.isEmpty {
            return "Tournament opening: Black's first stone must be center"
        }
        return "Tournament opening: Black's second stone must be at least 3 intersections from center"
    }

    private func removeCapturedPairs(fromRow row: Int, col: Int, player: Stone) -> [BoardPoint] {
        var captured: [BoardPoint] = []
        let opponent = player.opposite
        for (dr, dc) in directions + directions.map({ (-$0.0, -$0.1) }) {
            let first = (row + dr, col + dc)
            let second = (row + dr * 2, col + dc * 2)
            let third = (row + dr * 3, col + dc * 3)
            guard isOnBoard(first.0, first.1),
                  isOnBoard(second.0, second.1),
                  isOnBoard(third.0, third.1),
                  board[first.0][first.1] == opponent,
                  board[second.0][second.1] == opponent,
                  board[third.0][third.1] == player
            else { continue }
            board[first.0][first.1] = .empty
            board[second.0][second.1] = .empty
            captured.append(BoardPoint(row: first.0, col: first.1))
            captured.append(BoardPoint(row: second.0, col: second.1))
        }
        return captured
    }

    private func hasFiveInRow(fromRow row: Int, col: Int, player: Stone) -> Bool {
        for (dr, dc) in directions {
            var count = 1
            count += countStones(row: row, col: col, dr: dr, dc: dc, player: player)
            count += countStones(row: row, col: col, dr: -dr, dc: -dc, player: player)
            if count >= 5 { return true }
        }
        return false
    }

    private func countStones(row: Int, col: Int, dr: Int, dc: Int, player: Stone) -> Int {
        var count = 0
        var r = row + dr
        var c = col + dc
        while isOnBoard(r, c), board[r][c] == player {
            count += 1
            r += dr
            c += dc
        }
        return count
    }

    private func capturePairs(for player: Stone) -> Int {
        player == .black ? capturesByBlack : capturesByWhite
    }

    private func isOnBoard(_ row: Int, _ col: Int) -> Bool {
        row >= 0 && row < boardSize && col >= 0 && col < boardSize
    }

    private func saveURL() throws -> URL {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Pente", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("saved-game.json")
    }

    private func rebuildGame(through moveCount: Int) {
        let players = (blackPlayer, whitePlayer, aiStrength, tournamentOpening)
        let replay = Array(moveHistory.prefix(moveCount))
        isRestoringFromLoad = true
        board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize)
        currentPlayer = .black
        capturesByBlack = 0
        capturesByWhite = 0
        moveHistory = []
        gameOver = false
        winner = nil
        lastMoveRow = nil
        lastMoveCol = nil
        blackPlayer = players.0
        whitePlayer = players.1
        aiStrength = players.2
        tournamentOpening = players.3
        isRestoringFromLoad = false

        for record in replay {
            playMove(row: record.row, col: record.col)
        }
        if moveHistory.isEmpty {
            statusMessage = "Black to move"
        }
        saveGameToDisk(manual: false)
    }

    private static func bestMove(
        for player: Stone,
        board: [[Stone]],
        capturesBlack: Int,
        capturesWhite: Int,
        historyCount: Int,
        tournamentOpening: Bool,
        strength: AIStrength
    ) -> (Int, Int)? {
        let size = board.count
        let center = size / 2
        if tournamentOpening, historyCount == 0 {
            return (center, center)
        }

        let legal = candidateMoves(
            board: board,
            player: player,
            historyCount: historyCount,
            tournamentOpening: tournamentOpening,
            limit: strength.candidateLimit
        )
        guard !legal.isEmpty else { return nil }

        var best = legal[0]
        var bestScore = Int.min
        for move in legal {
            let score = evaluate(
                move: move,
                player: player,
                board: board,
                capturesBlack: capturesBlack,
                capturesWhite: capturesWhite,
                strength: strength
            )
            if score > bestScore {
                bestScore = score
                best = move
            }
        }
        return best
    }

    private static func candidateMoves(
        board: [[Stone]],
        player: Stone,
        historyCount: Int,
        tournamentOpening: Bool,
        limit: Int
    ) -> [(Int, Int)] {
        let size = board.count
        let center = size / 2
        if tournamentOpening, historyCount == 2, player == .black {
            return [(center - 3, center), (center + 3, center), (center, center - 3), (center, center + 3)]
                .filter { isOnBoard($0.0, $0.1, size: size) && board[$0.0][$0.1] == .empty }
        }

        var candidates = Set<[Int]>()
        for row in 0..<size {
            for col in 0..<size where board[row][col] != .empty {
                for dr in -2...2 {
                    for dc in -2...2 {
                        let r = row + dr
                        let c = col + dc
                        if isOnBoard(r, c, size: size), board[r][c] == .empty {
                            candidates.insert([r, c])
                        }
                    }
                }
            }
        }
        if candidates.isEmpty {
            candidates.insert([center, center])
        }
        return candidates
            .map { ($0[0], $0[1]) }
            .sorted {
                let left = abs($0.0 - center) + abs($0.1 - center)
                let right = abs($1.0 - center) + abs($1.1 - center)
                return left < right
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func evaluate(
        move: (Int, Int),
        player: Stone,
        board: [[Stone]],
        capturesBlack: Int,
        capturesWhite: Int,
        strength: AIStrength
    ) -> Int {
        var trial = board
        trial[move.0][move.1] = player
        let captured = simulatedCaptures(row: move.0, col: move.1, player: player, board: &trial)
        let myCaptures = (player == .black ? capturesBlack : capturesWhite) + captured / 2
        if myCaptures >= 5 || lineLength(row: move.0, col: move.1, player: player, board: trial) >= 5 {
            return 1_000_000
        }

        let opponent = player.opposite
        var score = myCaptures * 12_000
        score += captured * 4_000
        score += patternScore(row: move.0, col: move.1, player: player, board: trial)
        score += centerScore(row: move.0, col: move.1, size: board.count)

        if strength != .fast {
            score += defensiveScore(after: trial, opponent: opponent)
        }
        if strength == .strong {
            score -= opponentBestReplyThreat(after: trial, opponent: opponent) / 2
        }
        return score
    }

    private static func patternScore(row: Int, col: Int, player: Stone, board: [[Stone]]) -> Int {
        let longest = lineLength(row: row, col: col, player: player, board: board)
        let openEnds = openEndCount(row: row, col: col, player: player, board: board)
        switch longest {
        case 4: return 90_000 + openEnds * 8_000
        case 3: return 18_000 + openEnds * 3_000
        case 2: return 4_000 + openEnds * 900
        default: return openEnds * 200
        }
    }

    private static func defensiveScore(after board: [[Stone]], opponent: Stone) -> Int {
        var best = 0
        for row in 0..<board.count {
            for col in 0..<board.count where board[row][col] == .empty {
                var trial = board
                trial[row][col] = opponent
                let length = lineLength(row: row, col: col, player: opponent, board: trial)
                if length >= 5 { best = max(best, 180_000) }
                if length == 4 { best = max(best, 42_000) }
                if length == 3 { best = max(best, 9_000) }
            }
        }
        return best
    }

    private static func opponentBestReplyThreat(after board: [[Stone]], opponent: Stone) -> Int {
        var best = 0
        for move in candidateMoves(board: board, player: opponent, historyCount: 99, tournamentOpening: false, limit: 36) {
            var trial = board
            trial[move.0][move.1] = opponent
            if lineLength(row: move.0, col: move.1, player: opponent, board: trial) >= 5 {
                best = max(best, 220_000)
            } else {
                best = max(best, patternScore(row: move.0, col: move.1, player: opponent, board: trial))
            }
        }
        return best
    }

    private static func simulatedCaptures(row: Int, col: Int, player: Stone, board: inout [[Stone]]) -> Int {
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
        let opponent = player.opposite
        var captured = 0
        for (dr, dc) in directions + directions.map({ (-$0.0, -$0.1) }) {
            let first = (row + dr, col + dc)
            let second = (row + dr * 2, col + dc * 2)
            let third = (row + dr * 3, col + dc * 3)
            guard isOnBoard(first.0, first.1, size: board.count),
                  isOnBoard(second.0, second.1, size: board.count),
                  isOnBoard(third.0, third.1, size: board.count),
                  board[first.0][first.1] == opponent,
                  board[second.0][second.1] == opponent,
                  board[third.0][third.1] == player
            else { continue }
            board[first.0][first.1] = .empty
            board[second.0][second.1] = .empty
            captured += 2
        }
        return captured
    }

    private static func lineLength(row: Int, col: Int, player: Stone, board: [[Stone]]) -> Int {
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
        return directions.map { dr, dc in
            1
            + count(row: row, col: col, dr: dr, dc: dc, player: player, board: board)
            + count(row: row, col: col, dr: -dr, dc: -dc, player: player, board: board)
        }.max() ?? 1
    }

    private static func openEndCount(row: Int, col: Int, player: Stone, board: [[Stone]]) -> Int {
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
        var ends = 0
        for (dr, dc) in directions {
            ends += openEnd(row: row, col: col, dr: dr, dc: dc, player: player, board: board) ? 1 : 0
            ends += openEnd(row: row, col: col, dr: -dr, dc: -dc, player: player, board: board) ? 1 : 0
        }
        return ends
    }

    private static func openEnd(row: Int, col: Int, dr: Int, dc: Int, player: Stone, board: [[Stone]]) -> Bool {
        var r = row + dr
        var c = col + dc
        while isOnBoard(r, c, size: board.count), board[r][c] == player {
            r += dr
            c += dc
        }
        return isOnBoard(r, c, size: board.count) && board[r][c] == .empty
    }

    private static func count(row: Int, col: Int, dr: Int, dc: Int, player: Stone, board: [[Stone]]) -> Int {
        var count = 0
        var r = row + dr
        var c = col + dc
        while isOnBoard(r, c, size: board.count), board[r][c] == player {
            count += 1
            r += dr
            c += dc
        }
        return count
    }

    private static func centerScore(row: Int, col: Int, size: Int) -> Int {
        let center = size / 2
        return max(0, 200 - ((abs(row - center) + abs(col - center)) * 10))
    }

    private static func isOnBoard(_ row: Int, _ col: Int, size: Int) -> Bool {
        row >= 0 && row < size && col >= 0 && col < size
    }
}
