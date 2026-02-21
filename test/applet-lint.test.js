const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const appletSource = fs.readFileSync(path.join(ROOT, 'applet.js'), 'utf8');
const metadata = JSON.parse(fs.readFileSync(path.join(ROOT, 'metadata.json'), 'utf8'));

describe('applet.js safety checks', () => {
    describe('cleanup on removal', () => {
        it('has on_applet_removed_from_panel method', () => {
            assert.ok(
                appletSource.includes('on_applet_removed_from_panel'),
                'missing on_applet_removed_from_panel method'
            );
        });

        it('destroys window buttons in on_applet_removed_from_panel', () => {
            // Extract the on_applet_removed_from_panel method body
            const methodMatch = appletSource.match(
                /on_applet_removed_from_panel\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find on_applet_removed_from_panel body');
            const body = methodMatch[1];

            assert.ok(
                body.includes('.destroy()'),
                'on_applet_removed_from_panel must call .destroy() on window buttons'
            );
            assert.ok(
                body.includes('this._windows'),
                'on_applet_removed_from_panel must reference this._windows'
            );
        });
    });

    describe('signal management', () => {
        it('does not use raw this.actor.connect for allocation signals', () => {
            // Look for raw connect patterns that bypass SignalManager
            const rawConnectPattern = /this\._allocationSignalId\s*=\s*this\.actor\.connect/;
            assert.ok(
                !rawConnectPattern.test(appletSource),
                'found raw this.actor.connect for allocation signal — use this.signals.connect instead'
            );
        });

        it('calls signals.disconnectAllSignals in cleanup', () => {
            const methodMatch = appletSource.match(
                /on_applet_removed_from_panel\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch);
            const body = methodMatch[1];
            assert.ok(
                body.includes('disconnectAllSignals'),
                'on_applet_removed_from_panel must call signals.disconnectAllSignals()'
            );
        });
    });

    describe('settings UUID', () => {
        it('uses the correct UUID from metadata.json', () => {
            const uuid = metadata.uuid;
            const settingsPattern = new RegExp(
                `new Settings\\.AppletSettings\\(this,\\s*"${uuid.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"`
            );
            assert.ok(
                settingsPattern.test(appletSource),
                `applet.js must use Settings UUID "${uuid}" matching metadata.json`
            );
        });
    });

    describe('timer safety', () => {
        it('clears _updateIconGeometryTimeoutId after source_remove', () => {
            // After source_remove, the ID should be set to 0 before any new timeout_add
            const pattern = /source_remove\(this\._updateIconGeometryTimeoutId\);\s*\n\s*this\._updateIconGeometryTimeoutId\s*=\s*0/;
            assert.ok(
                pattern.test(appletSource),
                '_updateIconGeometryTimeoutId must be set to 0 after source_remove'
            );
        });
    });
});
