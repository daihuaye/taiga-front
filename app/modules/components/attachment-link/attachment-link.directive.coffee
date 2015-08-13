AttachmentLinkDirective = ($parse, lightboxFactory) ->
    link = (scope, el, attrs) ->
        attachment = $parse(attrs.tgAttachmentLink)(scope)

        el.on "click", (event) ->
            if taiga.isImage(attachment.getIn(['file', 'name']))
                event.preventDefault()

                scope.$apply ->
                    lightboxFactory.create('tg-lb-attachment-preview', {
                        class: 'lightbox lightbox-block'
                    }, {
                        file: attachment.get('file')
                    })

        scope.$on "$destroy", -> el.off()
    return {
        link: link
    }

AttachmentLinkDirective.$inject = [
    "$parse",
    "tgLightboxFactory"
]

angular.module("taigaComponents").directive("tgAttachmentLink", AttachmentLinkDirective)
