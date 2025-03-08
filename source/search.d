module chess_engine.search;

import core.atomic;
import std.algorithm;
import std.exception;
import std.logger;
import std.stdio;
import std.typecons;
import chess_engine.repr;

class StopException : Throwable {
    this(string file = __FILE__, size_t line = __LINE__) {
        super("StopException", file, line);
    }
}

const static float INFINITY = 1. / 0.;

struct SearchContext {
    shared bool isStopped = false;
}

struct AlphaBeta {
    // By convention we assume optimizing player is white, pessimizing is black
    // Lower bound for how good a position white can force for itself
    float alpha = -1. / 0.;
    // Lower bound for how good a position black can force for itself
    float beta = 1. / 0.;
}

static int numFiltered = 0;

struct SearchNode {
    MoveDest move;
    float depthEval = 0.0;
}

// TODO: Is there a more idiomatic way of doing this?
// Faster to sort indices than sort the array
struct SortOrder {
    ubyte[256] inds;
    MoveDest[] vals;

    this(MoveDest[] vals, int mult) {
        enforce(vals.length <= 256);
        this.vals = vals;
        foreach (i; 0 .. vals.length) {
            inds[i] = cast(ubyte) i;
        }
        inds[0 .. vals.length].sort!((i, j) => vals[i].eval * mult > vals[j].eval * mult);
    }

    auto range() const => inds[0 .. vals.length].map!(i => &vals[i]);
}

private Nullable!SearchNode pickBestMoveInner(
    const ref GameState source,
    AlphaBeta ab,
    shared SearchContext* context,
    int depth,
) {
    if (context.isStopped.atomicLoad() == true) {
        throw new StopException();
    }
    auto isBlack = source.turn == Player.black;
    int multForPlayer = isBlack ? -1 : 1;
    MoveDest[] children = source.validMoves;
    auto sortOrder = SortOrder(children, multForPlayer);
    const(MoveDest)* best = null;
    float bestScore = -INFINITY;
    foreach (const child; sortOrder.range) {
        bool shouldBreak = false;
        double score = child.eval;
        if (depth > 0) {
            auto cont = pickBestMoveInner(child.state, ab, context, depth - 1);
            if (cont.isNull) {
                continue;
            }
            score = cont.get.depthEval;
        }
        if (isBlack) {
            // Minimizing
            if (score < ab.alpha) {
                // Opponent won't permit this
                shouldBreak = true;
            }
            ab.beta = min(ab.beta, score);
        } else {
            // Maximizing
            if (score > ab.beta) {
                // Opponent won't permit this
                shouldBreak = true;
            }
            ab.alpha = max(ab.alpha, score);
        }
        float scoreForPlayer = score * multForPlayer;
        if (scoreForPlayer > bestScore) {
            bestScore = scoreForPlayer;
            best = child;
        }
        if (shouldBreak) {
            break;
        }
    }
    if (best == null) {
        return Nullable!SearchNode();
    }
    auto node = SearchNode(*best, bestScore * multForPlayer);
    return node.nullable;
}

MoveDest pickBestMove(const ref GameState source, int depth = 6, shared SearchContext* context = null) {
    shared SearchContext empty;
    if (context == null) {
        context = &empty;
    }
    AlphaBeta alphaBeta;
    auto startEvals = numEvals;
    auto bestMove = source.pickBestMoveInner(alphaBeta, context, depth).get;
    infof("Evaluated %d positions for depth % search", numEvals - startEvals, depth);
    infof("Best move: %s", bestMove);
    return bestMove.move;
}

unittest {
    // Free queen capture
    auto state = "qb1k4/1r6/8/8/8/8/8/Q2K4 w - - 0 1".parseFen;
    foreach (depth; 0 .. 3) {
        assert(state.pickBestMove(depth).move.getRepr == "a1a8");
    }
    // Queen will be taken back
    state = "rb1k4/1b6/8/8/8/8/8/Q2K4 w - - 0 1".parseFen;
    assert(state.pickBestMove(0).move.getRepr == "a1a8"); // Free Rook (TODO Quiescence)
    assert(state.pickBestMove(1).move.getRepr != "a1a8"); // Realize that the queen will be taken in response
    // Queen must be taken back
    state = "Qb1k4/1b6/8/8/8/8/8/3K4 b - - 0 1".parseFen;
    assert(state.pickBestMove(0).move.getRepr == "b7a8");
    state = "r1bqkbnr/pppppppp/2n5/8/3P4/6P1/PPP1PP1P/RNBQKBNR b KQkq - 0 1".parseFen;
    assert(state.pickBestMove(1).move.getRepr != "c6d4");
}

// TODO: We should be keeping some stuff from the previous iteration. This is more ad-hoc
MoveDest pickBestMoveIterativeDeepening(
    const ref GameState source,
    shared SearchContext* context,
    int startNumIterations = 3,
) {
    MoveDest move;
    bool hasMove = false;
    try {
        // We aren't ever going above 15
        foreach (depth; startNumIterations .. 15) {
            MoveDest found = source.pickBestMove(depth, context);
            move = found;
            hasMove = true;
        }
    } catch (StopException) {
    }
    enforce(hasMove);
    return move;
}
