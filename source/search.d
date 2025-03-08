module chess_engine.search;

import std.algorithm;
import std.exception;
import std.logger;
import std.stdio;
import std.typecons;
import chess_engine.repr;

const static float INFINITY = 1. / 0.;

// TODO: Rename?
struct SearchCtx {
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

private Nullable!SearchNode pickBestMoveInner(const ref GameState source, SearchCtx ctx, int depth) {
    auto isBlack = source.turn == Player.black;
    int multForPlayer = isBlack ? -1 : 1;
    MoveDest[] children = source.validMoves;
    children[].sort!((a, b) => multForPlayer * a.eval < multForPlayer * b.eval);
    const(MoveDest)* best = null;
    float bestScore = -INFINITY;
    foreach (const ref child; children) {
        bool shouldBreak = false;
        double score = child.eval;
        if (depth > 0) {
            auto cont = pickBestMoveInner(child.state, ctx, depth - 1);
            if (cont.isNull) {
                continue;
            }
            score = cont.get.depthEval;
        }
        if (isBlack) {
            // Minimizing
            if (score < ctx.alpha) {
                // Opponent won't permit this
                shouldBreak = true;
            }
            ctx.beta = min(ctx.beta, score);
        } else {
            // Maximizing
            if (score > ctx.beta) {
                // Opponent won't permit this
                shouldBreak = true;
            }
            ctx.alpha = max(ctx.alpha, score);
        }
        float scoreForPlayer = score * multForPlayer;
        if (scoreForPlayer > bestScore) {
            bestScore = scoreForPlayer;
            best = &child;
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

MoveDest pickBestMove(const ref GameState source, int depth = 5) {
    SearchCtx ctx;
    auto startEvals = numEvals;
    auto bestMove = source.pickBestMoveInner(ctx, depth).get;
    infof("Evaluated %d positions", numEvals - startEvals);
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
}
