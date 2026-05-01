#!/usr/bin/env python3
"""XTest actions CLI — synthetic input that works inside Clutter pushModal.

Uses python-xlib XTest extension (unlike xdotool which doesn't work with
Mutter/Clutter compositors).

Usage (run on VM with DISPLAY=:0):
    python3 xtest-actions.py click X Y [--button=N]
    python3 xtest-actions.py drag SX SY EX EY [--steps=N]
    python3 xtest-actions.py key KEYSYM
    python3 xtest-actions.py move X Y
"""

import sys
import time
import argparse

from Xlib import X, display, XK
from Xlib.ext import xtest


def get_display():
    return display.Display()


def cmd_click(args):
    d = get_display()
    button = args.button or 1
    xtest.fake_input(d, X.MotionNotify, x=args.x, y=args.y)
    d.sync()
    time.sleep(0.02)
    xtest.fake_input(d, X.ButtonPress, button)
    d.sync()
    time.sleep(0.05)
    xtest.fake_input(d, X.ButtonRelease, button)
    d.sync()


def cmd_drag(args):
    d = get_display()
    steps = args.steps or 10
    button = args.button or 1

    # Move to start
    xtest.fake_input(d, X.MotionNotify, x=args.sx, y=args.sy)
    d.sync()
    time.sleep(0.05)

    # Press
    xtest.fake_input(d, X.ButtonPress, button)
    d.sync()
    time.sleep(0.05)

    # Interpolate motion
    for i in range(1, steps + 1):
        t = i / steps
        ix = int(args.sx + (args.ex - args.sx) * t)
        iy = int(args.sy + (args.ey - args.sy) * t)
        xtest.fake_input(d, X.MotionNotify, x=ix, y=iy)
        d.sync()
        time.sleep(0.02)

    # Release
    xtest.fake_input(d, X.ButtonRelease, button)
    d.sync()


def cmd_key(args):
    d = get_display()
    keysym = XK.string_to_keysym(args.keysym)
    if keysym == 0:
        print(f"Unknown keysym: {args.keysym}", file=sys.stderr)
        sys.exit(1)
    keycode = d.keysym_to_keycode(keysym)
    if keycode == 0:
        print(f"No keycode for keysym: {args.keysym}", file=sys.stderr)
        sys.exit(1)
    xtest.fake_input(d, X.KeyPress, keycode)
    d.sync()
    time.sleep(0.02)
    xtest.fake_input(d, X.KeyRelease, keycode)
    d.sync()


def cmd_move(args):
    d = get_display()
    xtest.fake_input(d, X.MotionNotify, x=args.x, y=args.y)
    d.sync()


def main():
    parser = argparse.ArgumentParser(description='XTest synthetic input CLI')
    sub = parser.add_subparsers(dest='command', required=True)

    p_click = sub.add_parser('click', help='Click at x,y')
    p_click.add_argument('x', type=int)
    p_click.add_argument('y', type=int)
    p_click.add_argument('--button', type=int, default=1)

    p_drag = sub.add_parser('drag', help='Drag from sx,sy to ex,ey')
    p_drag.add_argument('sx', type=int)
    p_drag.add_argument('sy', type=int)
    p_drag.add_argument('ex', type=int)
    p_drag.add_argument('ey', type=int)
    p_drag.add_argument('--steps', type=int, default=10)
    p_drag.add_argument('--button', type=int, default=1)

    p_key = sub.add_parser('key', help='Press+release a key')
    p_key.add_argument('keysym', help='X keysym name (e.g. Escape, Return, a)')

    p_move = sub.add_parser('move', help='Move pointer to x,y')
    p_move.add_argument('x', type=int)
    p_move.add_argument('y', type=int)

    args = parser.parse_args()

    commands = {
        'click': cmd_click,
        'drag': cmd_drag,
        'key': cmd_key,
        'move': cmd_move,
    }
    commands[args.command](args)


if __name__ == '__main__':
    main()
