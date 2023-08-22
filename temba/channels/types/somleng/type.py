from django.utils.translation import gettext_lazy as _

from temba.channels.types.somleng.views import ClaimView
from temba.contacts.models import URN

from ...models import Channel, ChannelType


class SomlengType(ChannelType):
    """
    An Somleng channel

    Callback status information (https://www.twilio.com/docs/voice/twiml#callstatus-values):

        queued: The call is ready and waiting in line before going out.
        ringing: The call is currently ringing.
        in-progress: The call was answered and is currently in progress.
        completed: The call was answered and has ended normally.
        busy: The caller received a busy signal.
        failed: The call could not be completed as dialed, most likely because the phone number was non-existent.
        no-answer: The call ended without being answered.
        canceled: The call was canceled via the REST API while queued or ringing.

    """

    code = "TW"
    category = ChannelType.Category.PHONE

    name = "Somleng"
    slug = "somleng"

    courier_url = r"^tw/(?P<uuid>[a-z0-9\-]+)/(?P<action>receive|status)$"

    schemes = [URN.TEL_SCHEME]
    max_length = 1600

    claim_view = ClaimView
    claim_blurb = _("Connect to a Somleng instance.")

    configuration_blurb = _(
        "To finish configuring your Somleng channel you'll need to add the following URL to your Somleng instance."
    )
    configuration_urls = (
        ChannelType.Endpoint(
            courier="receive",
            label="Incoming Messages",
            help=_("New incoming messages should be sent to this endpoint."),
            roles=(Channel.ROLE_RECEIVE,),
        ),
        ChannelType.Endpoint(
            courier="status",
            label="Message Status Updates",
            help=_("Message status updates should be sent to this endpoint."),
            roles=(Channel.ROLE_SEND,),
        ),
        ChannelType.Endpoint(
            mailroom="incoming",
            label="Incoming Calls",
            help=_("New incoming calls should be sent to this endpoint."),
            roles=(Channel.ROLE_ANSWER,),
        ),
        ChannelType.Endpoint(
            mailroom="status",
            label="Call Status Updates",
            help=_("Call status updates should be sent to this endpoint."),
            roles=(Channel.ROLE_CALL, Channel.ROLE_ANSWER),
        ),
    )

    def get_error_ref_url(self, channel, code: str) -> str:
        return f"https://www.twilio.com/docs/api/errors/{code}"
