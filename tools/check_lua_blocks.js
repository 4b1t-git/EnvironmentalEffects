"use strict";
// Proves every shipped Lua file's blocks balance.
//
// This is NOT a Lua parser and does not pretend to be one. It catches exactly
// one class of mistake -- a missing or extra `end`, or an unclosed `repeat` --
// which is the one that turns a mod into a mod that silently does not load.
// Nothing else in this toolchain reads the Lua at all: the pure-logic tests
// exercise a JavaScript mirror of the simulation, not the shipped files, so a
// syntax error in them reaches the game unopposed. That is the same shape of
// failure that cost a full debugging session when a reloaded weapon rendered
// dry, and it is worth a cheap guard.
//
// A real parser would need a Lua runtime, and the project takes no new
// dependencies, so this uses only Node.
//
// Blocks that require `end`: `function`, `if`, and `do`. `for` and `while` are
// deliberately NOT counted -- each is followed by its own `do`, which is the
// token that actually opens the block, so counting both would double count.
// `elseif` and `else` continue a block rather than opening one. `repeat` pairs
// with `until` instead of `end`.

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const luaRoot = path.join(root, "mod/42/media/lua");

// Removes comments and string literals so their contents cannot be mistaken for
// keywords. Long-bracket forms ([[ ]], [==[ ]==]) are handled for both.
function strip(source) {
    let out = "";
    let i = 0;
    while (i < source.length) {
        const rest = source.slice(i);

        const longOpen = /^(?:--)?\[(=*)\[/.exec(rest);
        if (longOpen) {
            const close = "]" + longOpen[1] + "]";
            const end = source.indexOf(close, i + longOpen[0].length);
            i = end === -1 ? source.length : end + close.length;
            out += " ";
            continue;
        }
        if (rest.startsWith("--")) {
            const end = source.indexOf("\n", i);
            i = end === -1 ? source.length : end;
            out += " ";
            continue;
        }
        const quote = source[i];
        if (quote === '"' || quote === "'") {
            i++;
            while (i < source.length && source[i] !== quote) {
                i += source[i] === "\\" ? 2 : 1;
            }
            i++;
            out += " ";
            continue;
        }
        out += source[i];
        i++;
    }
    return out;
}

function check(file) {
    const text = strip(fs.readFileSync(file, "utf8"));
    let depth = 0;
    let repeats = 0;
    for (const match of text.matchAll(/\b(function|if|do|end|repeat|until)\b/g)) {
        switch (match[1]) {
            case "function":
            case "if":
            case "do":
                depth++;
                break;
            case "end":
                depth--;
                if (depth < 0) {
                    throw new Error(`${path.relative(root, file)}: an 'end' closes a block that was never opened`);
                }
                break;
            case "repeat":
                repeats++;
                break;
            case "until":
                repeats--;
                if (repeats < 0) {
                    throw new Error(`${path.relative(root, file)}: an 'until' with no 'repeat'`);
                }
                break;
        }
    }
    if (depth !== 0) {
        throw new Error(
            `${path.relative(root, file)}: ${depth} block(s) left unclosed; ` +
            `${depth > 0 ? "an 'end' is missing" : "there is one 'end' too many"}`
        );
    }
    if (repeats !== 0) {
        throw new Error(`${path.relative(root, file)}: ${repeats} 'repeat' without 'until'`);
    }
}

function walk(dir) {
    const found = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) found.push(...walk(full));
        else if (entry.name.endsWith(".lua")) found.push(full);
    }
    return found;
}

const files = walk(luaRoot);
if (files.length === 0) throw new Error("no Lua files found to check");
for (const file of files) check(file);
console.log(`check_lua_blocks: PASS (${files.length} files)`);
