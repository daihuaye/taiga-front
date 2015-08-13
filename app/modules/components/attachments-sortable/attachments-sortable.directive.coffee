AttachmentSortableDirective = ($parse) ->
    link = (scope, el, attrs) ->
        callback = $parse(attrs.tgAttachmentsSortable)

        el.sortable({
            items: "div[tg-bind-scope]"
            handle: "a.settings.icon.icon-drag-v"
            containment: ".attachments"
            dropOnEmpty: true
            helper: 'clone'
            scroll: false
            tolerance: "pointer"
            placeholder: "sortable-placeholder single-attachment"
        })

        el.on "sortstop", (event, ui) ->
            attachment = ui.item.scope().attachment
            newIndex = ui.item.index()

            scope.$apply () ->
                callback(scope, {attachment: attachment, index: newIndex})

        scope.$on "$destroy", -> el.off()

    return {
        link: link
    }

AttachmentSortableDirective.$inject = [
    "$parse"
]

angular.module("taigaComponents").directive("tgAttachmentsSortable", AttachmentSortableDirective)
