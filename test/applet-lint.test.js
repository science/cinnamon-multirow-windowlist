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

        it('uses actor allocation width in _onAllocationChanged (not parent zone width)', () => {
            const methodMatch = appletSource.match(
                /_onAllocationChanged\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _onAllocationChanged body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('get_allocation_box'),
                '_onAllocationChanged must use get_allocation_box() for width (not parent.get_width() which returns full zone width)'
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

    describe('window grouping by app', () => {
        it('imports calcGroupedInsertionIndex from helpers', () => {
            assert.ok(
                appletSource.includes('calcGroupedInsertionIndex'),
                'applet.js must import calcGroupedInsertionIndex from helpers'
            );
        });

        it('_addWindow uses insert_child_at_index for grouped insertion', () => {
            const methodMatch = appletSource.match(
                /^\s{4}_addWindow\s*\([\s\S]*?\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _addWindow body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('insert_child_at_index'),
                '_addWindow must use insert_child_at_index for grouped window placement'
            );
        });

        it('_addWindow calls calcGroupedInsertionIndex', () => {
            const methodMatch = appletSource.match(
                /^\s{4}_addWindow\s*\([\s\S]*?\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _addWindow body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('calcGroupedInsertionIndex'),
                '_addWindow must call calcGroupedInsertionIndex to compute insertion position'
            );
        });

        it('_addWindow checks groupWindows setting', () => {
            const methodMatch = appletSource.match(
                /^\s{4}_addWindow\s*\([\s\S]*?\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _addWindow body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('groupWindows'),
                '_addWindow must check this.groupWindows setting to gate grouped insertion'
            );
        });
    });

    describe('multi-row drag-and-drop', () => {
        it('imports calcDragInsertionIndex from helpers', () => {
            assert.ok(
                appletSource.includes('calcDragInsertionIndex'),
                'applet.js must import calcDragInsertionIndex from helpers'
            );
        });

        it('applet-level handleDragOver calls calcDragInsertionIndex', () => {
            // There are two handleDragOver methods — one on AppMenuButton (returns
            // CONTINUE/NO_DROP for drag-to-window-open) and one on MyApplet (handles
            // reordering). We need the one that references _dragPlaceholder.
            const matches = appletSource.matchAll(
                /^\s{4}handleDragOver\s*\([\s\S]*?\)\s*\{([\s\S]*?)^\s{4}\}/gm
            );
            let appletBody = null;
            for (const m of matches) {
                if (m[1].includes('_dragPlaceholder')) {
                    appletBody = m[1];
                    break;
                }
            }
            assert.ok(appletBody, 'could not find applet-level handleDragOver (with _dragPlaceholder)');
            assert.ok(
                appletBody.includes('calcDragInsertionIndex'),
                'applet handleDragOver must use calcDragInsertionIndex for 2D-aware positioning'
            );
        });

        it('_onDragBegin conditionalizes _overrideY on row count', () => {
            const methodMatch = appletSource.match(
                /_onDragBegin\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _onDragBegin body');
            const body = methodMatch[1];
            // Multi-row drag needs Y freedom — _onDragBegin must check _computedRows
            assert.ok(
                body.includes('_computedRows'),
                '_onDragBegin must check _computedRows to conditionalize _overrideY for multi-row'
            );
        });
    });

    describe('spacious float-left layout', () => {
        // Extract _allocate method body for all tests in this block
        const allocateMatch = appletSource.match(
            /_allocate\s*\([\s\S]*?\)\s*\{([\s\S]*?)^\s{4}\}/m
        );
        const allocateBody = allocateMatch ? allocateMatch[1] : '';

        it('uses Pango indent for first-line text offset', () => {
            assert.ok(allocateBody.includes('set_indent'), '_allocate must call set_indent for first-line text offset');
            assert.ok(allocateBody.includes('Pango.SCALE'), '_allocate must use Pango.SCALE for indent units');
            assert.ok(allocateBody.includes('_spaciousIndent'), '_allocate must store indent in _spaciousIndent for paint handler');
        });

        it('accesses ClutterText for Pango layout', () => {
            // The spacious branch needs get_clutter_text to access the Pango layout
            assert.ok(
                allocateBody.includes('get_clutter_text'),
                'spacious branch must call get_clutter_text to access Pango layout'
            );
        });

        it('has paint handler for indent persistence', () => {
            // set_indent on PangoLayout is lost when ClutterText recreates its
            // layout cache. A paint signal handler re-applies the stored indent.
            assert.ok(
                appletSource.includes("connect('paint'") || appletSource.includes('connect("paint"'),
                'must connect to ClutterText paint signal for indent persistence'
            );
            assert.ok(
                appletSource.includes('_spaciousIndent'),
                'must use _spaciousIndent to persist indent value across paint cycles'
            );
        });

        it('caps icon size to label line height', () => {
            assert.ok(
                allocateBody.includes('labelNatHeight'),
                'spacious branch must use labelNatHeight to cap icon size'
            );
            assert.ok(
                allocateBody.includes('maxIconSize'),
                'spacious branch must compute maxIconSize from label line height'
            );
        });

        it('snaps label height to whole-line boundary', () => {
            assert.ok(
                allocateBody.includes('maxLines'),
                'spacious branch must compute maxLines for whole-line snap'
            );
            assert.ok(
                allocateBody.includes('maxLines * lineHeight'),
                'spacious branch must use maxLines * lineHeight to snap label height'
            );
        });

        it('does not use iconBottom in spacious branch', () => {
            // The old spacious layout used iconBottom to stack label below icon.
            // Float-left layout should not use this pattern.
            const spaciousBranch = allocateBody.match(/\} else \{[\s\S]*?Spacious mode[\s\S]*?(?=if \(!this\.progressOverlay)/);
            assert.ok(spaciousBranch, 'could not find spacious else-branch in _allocate');
            assert.ok(
                !spaciousBranch[0].includes('iconBottom'),
                'spacious branch must not use iconBottom — float-left layout positions label at same y as icon'
            );
        });
    });

});
