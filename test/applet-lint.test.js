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

    describe('FlowLayout min_width override', () => {
        it('sets min_width = 0 in constructor after creating manager_container', () => {
            // After add_actor(manager_container), the constructor must set min_width = 0
            // to prevent FlowLayout's inflated min_width from squeezing panel zones
            const pattern = /add_actor\s*\(\s*this\.manager_container\s*\)[\s\S]*?manager_container\.min_width\s*=\s*0/;
            assert.ok(
                pattern.test(appletSource),
                'constructor must set manager_container.min_width = 0 after add_actor'
            );
        });

        it('re-asserts min_width = 0 in _onAllocationChanged after set_width', () => {
            const methodMatch = appletSource.match(
                /_onAllocationChanged\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _onAllocationChanged body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('min_width = 0'),
                '_onAllocationChanged must re-assert manager_container.min_width = 0 after set_width'
            );
        });

        it('sets min_width = 0 in on_orientation_changed for horizontal', () => {
            // After set_layout_manager in the horizontal branch, min_width must be set to 0
            const pattern = /on_orientation_changed[\s\S]*?FlowLayout[\s\S]*?set_layout_manager[\s\S]*?min_width\s*=\s*0/;
            assert.ok(
                pattern.test(appletSource),
                'on_orientation_changed must set manager_container.min_width = 0 after FlowLayout swap'
            );
        });
    });

    describe('adaptive button width', () => {
        it('_recomputeAdaptiveRows computes effective button width', () => {
            const methodMatch = appletSource.match(
                /_recomputeAdaptiveRows\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _recomputeAdaptiveRows body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('_effectiveButtonWidth'),
                '_recomputeAdaptiveRows must compute _effectiveButtonWidth'
            );
        });

        it('_getPreferredWidth uses _effectiveButtonWidth', () => {
            const methodMatch = appletSource.match(
                /_getPreferredWidth\s*\([\s\S]*?\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _getPreferredWidth body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('_effectiveButtonWidth'),
                '_getPreferredWidth must use _effectiveButtonWidth instead of raw buttonWidth'
            );
        });

        it('updateLabelVisible checks _iconOnlyMode', () => {
            const methodMatch = appletSource.match(
                /updateLabelVisible\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find updateLabelVisible body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('_iconOnlyMode'),
                'updateLabelVisible must check _iconOnlyMode to hide labels when buttons are too narrow'
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
