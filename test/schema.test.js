const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const schema = JSON.parse(fs.readFileSync(path.join(ROOT, 'settings-schema.json'), 'utf8'));
const metadata = JSON.parse(fs.readFileSync(path.join(ROOT, 'metadata.json'), 'utf8'));

describe('metadata.json', () => {
    it('has the correct UUID', () => {
        assert.equal(metadata.uuid, 'multirow-window-list@cinnamon');
    });

    it('has updated name', () => {
        assert.equal(metadata.name, 'Multi-Row Window List');
    });

    it('retains windowattentionhandler role', () => {
        assert.equal(metadata.role, 'windowattentionhandler');
    });
});

describe('settings-schema.json', () => {
    describe('Multi-Row section', () => {
        it('has a multi-row section header', () => {
            assert.ok(schema['section-multirow'], 'missing section-multirow');
            assert.equal(schema['section-multirow'].type, 'section');
        });

        it('has max-rows as spinbutton with correct range', () => {
            const s = schema['max-rows'];
            assert.ok(s, 'missing max-rows');
            assert.equal(s.type, 'spinbutton');
            assert.equal(s.default, 2);
            assert.equal(s.min, 1);
            assert.equal(s.max, 4);
        });

        it('has group-windows switch defaulting to true', () => {
            const s = schema['group-windows'];
            assert.ok(s, 'missing group-windows');
            assert.equal(s.type, 'switch');
            assert.equal(s.default, true);
        });
    });

    describe('Button Appearance section', () => {
        it('has a button-appearance section header', () => {
            assert.ok(schema['section-button-appearance'], 'missing section-button-appearance');
            assert.equal(schema['section-button-appearance'].type, 'section');
        });

        it('has icon-size-override spinbutton (0=auto, max 64)', () => {
            const s = schema['icon-size-override'];
            assert.ok(s, 'missing icon-size-override');
            assert.equal(s.type, 'spinbutton');
            assert.equal(s.default, 0);
            assert.equal(s.min, 0);
            assert.equal(s.max, 64);
            assert.equal(s.step, 2);
        });

        it('has label-font-size spinbutton (0=system default, max 24)', () => {
            const s = schema['label-font-size'];
            assert.ok(s, 'missing label-font-size');
            assert.equal(s.type, 'spinbutton');
            assert.equal(s.default, 0);
            assert.equal(s.min, 0);
            assert.equal(s.max, 24);
            assert.equal(s.step, 1);
        });

        it('has label-wrap switch defaulting to true', () => {
            const s = schema['label-wrap'];
            assert.ok(s, 'missing label-wrap');
            assert.equal(s.type, 'switch');
            assert.equal(s.default, true);
        });
    });

    describe('original settings preserved', () => {
        it('retains show-all-workspaces', () => {
            assert.ok(schema['show-all-workspaces']);
        });

        it('retains button-width', () => {
            assert.ok(schema['button-width']);
        });

        it('retains window-hover', () => {
            assert.ok(schema['window-hover']);
        });
    });
});
