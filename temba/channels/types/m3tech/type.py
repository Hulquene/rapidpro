from django.utils.translation import gettext_lazy as _

from temba.channels.views import AuthenticatedExternalClaimView
from temba.contacts.models import URN

from ...models import ChannelType


class M3TechType(ChannelType):
    """
    An M3 Tech channel (http://m3techservice.com)
    """

    code = "M3"
    category = ChannelType.Category.PHONE

    courier_url = r"^m3/(?P<uuid>[a-z0-9\-]+)/(?P<action>sent|delivered|failed|received|receive)$"

    name = "M3 Tech"

    claim_blurb = _("Easily add a two way number you have configured with %(link)s using their APIs.") % {
        "link": '<a target="_blank" href="http://m3techservice.com">M3 Tech</a>'
    }
    claim_view = AuthenticatedExternalClaimView

    schemes = [URN.TEL_SCHEME]
    max_length = 160

    configuration_blurb = _(
        "To finish configuring your connection you'll need to notify M3Tech of the following callback URLs."
    )
    configuration_urls = (
        ChannelType.Endpoint(courier="receive", label=_("Received URL")),
        ChannelType.Endpoint(courier="sent", label=_("Sent URL")),
        ChannelType.Endpoint(courier="delivered", label=_("Delivered URL")),
        ChannelType.Endpoint(courier="failed", label=_("Failed URL")),
    )

    available_timezones = ["Asia/Karachi"]
