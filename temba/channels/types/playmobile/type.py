from django.utils.translation import gettext_lazy as _

from temba.channels.models import ChannelType, ConfigUI
from temba.channels.types.playmobile.views import ClaimView
from temba.contacts.models import URN


class PlayMobileType(ChannelType):
    """
    A Play Mobile channel (http://playmobile.uz/)
    """

    courier_url = r"^pm/(?P<uuid>[a-z0-9\-]+)/(?P<action>receive)$"

    code = "PM"
    category = ChannelType.Category.PHONE

    name = "Play Mobile"
    available_timezones = ["Asia/Tashkent", "Asia/Samarkand"]

    claim_blurb = _(
        "If you are based in Uzbekistan, you can purchase a short code from %(link)s and connect it in a few simple "
        "steps."
    ) % {"link": '<a href="http://playmobile.uz/">Play Mobile</a>'}
    claim_view = ClaimView

    schemes = [URN.TEL_SCHEME]
    max_length = 160

    configuration_blurb = _(
        "To finish configuring your Play Mobile connection you'll need to notify Play Mobile of the following URL."
    )
    config_ui = ConfigUI(
        endpoints=[
            ConfigUI.Endpoint(
                courier="receive",
                label=_("Receive URL"),
                help=_("To receive incoming messages, you need to set the receive URL for your Play Mobile account."),
            ),
        ]
    )
