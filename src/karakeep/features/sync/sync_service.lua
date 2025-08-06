local EventListener = require('ui/widget/eventlistener')
local ButtonDialogTitle = require('ui/widget/buttondialogtitle')
local UIManager = require('ui/uimanager')
local _ = require('gettext')
local T = require('ffi/util').template
local logger = require('logger')

---@class SyncService : EventListener
---@field ui UI Reference to UI for accessing registered modules
local SyncService = EventListener:extend({})

---Show sync confirmation dialog when there are pending items
function SyncService:showSyncDialog()
    if not self.ui.karakeep_queue_manager:hasPendingItems() then
        local Notification = require('karakeep/shared/widgets/notification')
        logger.dbg('[SyncService] No pending items, showing notification')
        Notification:info(_('No pending items to sync'))
        return
    end

    -- Get count from bookmark queue specifically for display
    local bookmark_count = self.ui.karakeep_queue_manager.bookmark_queue:getCount()
    logger.info('[SyncService] Showing sync dialog for', bookmark_count, 'pending items')

    local message = bookmark_count == 1 and _('Sync 1 pending bookmark?')
        or T(_('Sync %1 pending bookmarks?'), bookmark_count)

    local sync_dialog
    sync_dialog = ButtonDialogTitle:new({
        title = message,
        title_align = 'center',
        buttons = {
            {
                {
                    text = _('Later'),
                    callback = function()
                        UIManager:close(sync_dialog)
                    end,
                },
                {
                    text = _('Sync Now'),
                    callback = function()
                        UIManager:close(sync_dialog)
                        -- Process queue after dialog closes
                        UIManager:nextTick(function()
                            self:syncAllPendingItems()
                        end)
                    end,
                },
            },
            {
                {
                    text = _('Clear Queue'),
                    callback = function()
                        UIManager:close(sync_dialog)
                        -- Show confirmation for destructive operation
                        UIManager:nextTick(function()
                            self:showClearQueueDialog(bookmark_count)
                        end)
                    end,
                },
            },
        },
    })

    UIManager:show(sync_dialog)
end

---Show confirmation dialog for clearing the queue
---@param queue_size number Number of items in queue
function SyncService:showClearQueueDialog(queue_size)
    local ConfirmBox = require('ui/widget/confirmbox')
    local Notification = require('karakeep/shared/widgets/notification')

    local message = T(
        _(
            'Are you sure you want to clear the sync queue?\n\nYou have %1 pending bookmarks that will be lost.\n\nThis action cannot be undone.'
        ),
        queue_size
    )

    local confirm_dialog = ConfirmBox:new({
        text = message,
        ok_text = _('Clear Queue'),
        ok_callback = function()
            self.ui.karakeep_queue_manager:clear()
            Notification:info(_('Sync queue cleared'))
        end,
        cancel_text = _('Cancel'),
    })

    UIManager:show(confirm_dialog)
end

---Sync all pending items (called after user confirms)
function SyncService:syncAllPendingItems()
    local Notification = require('karakeep/shared/widgets/notification')

    logger.info('[SyncService] Starting sync of all pending items')
    local results = self.ui.karakeep_queue_manager:syncPendingItems()

    -- Show result notification
    if results.total_items == 0 then
        Notification:info(_('No pending items to sync'))
    elseif results.success_count > 0 and results.error_count == 0 then
        Notification:success(T(_('Successfully synced %1 items'), results.success_count))
    elseif results.success_count > 0 and results.error_count > 0 then
        Notification:warn(
            T(_('Synced %1 items, %2 failed'), results.success_count, results.error_count)
        )
    else
        Notification:error(_('Failed to sync all items'))
    end
end

---Handle network connected event - show sync dialog if there are pending items
function SyncService:onNetworkConnected()
    logger.info('[SyncService] Network connected event received')

    -- Only show dialog if there are pending items
    if self.ui.karakeep_queue_manager:hasPendingItems() then
        logger.info('[SyncService] Showing sync dialog for pending items')
        self:showSyncDialog()
    end
end

return SyncService
