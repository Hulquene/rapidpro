import re

from temba.utils.languages import alpha2_to_alpha3

from .models import TemplateTranslation

VARIABLE_RE = re.compile(r"{{\s*(\d+)\s*}}")

STATUS_MAPPING = {
    "PENDING": TemplateTranslation.STATUS_PENDING,
    "APPROVED": TemplateTranslation.STATUS_APPROVED,
    "REJECTED": TemplateTranslation.STATUS_REJECTED,
}


def _extract_variables(content) -> list:
    """
    Extracts the unique and sorted variable names from a content string using handlebars syntax.
    """
    return list(sorted({m for m in VARIABLE_RE.findall(content)}))


def extract_components(raw: list) -> tuple:
    """
    Extracts components in our simplified format from payload of WhatsApp template components
    """

    components = []
    variables = []
    supported = True

    def add_variables(names: list, typ: str) -> dict:
        map = {}
        for name in names:
            variables.append({"type": typ})
            map[name] = len(variables) - 1
        return map

    for component in raw:
        comp_type = component["type"].upper()
        comp_text = component.get("text", "")

        if comp_type == "HEADER":
            comp_vars = {}

            if component.get("format", "TEXT") == "TEXT":
                comp_vars = add_variables(_extract_variables(comp_text), "text")
            else:
                supported = False

            components.append(
                {
                    "type": "header",
                    "name": "header",
                    "content": comp_text,
                    "variables": comp_vars,
                    "params": [{"type": "text"} for v in comp_vars],  # deprecated
                }
            )

        elif comp_type == "BODY":
            comp_vars = add_variables(_extract_variables(comp_text), "text")

            components.append(
                {
                    "type": "body",
                    "name": "body",
                    "content": comp_text,
                    "variables": comp_vars,
                    "params": [{"type": "text"} for v in comp_vars],  # deprecated
                }
            )

        elif comp_type == "FOOTER":
            components.append(
                {
                    "type": "footer",
                    "name": "footer",
                    "content": comp_text,
                    "variables": {},
                    "params": [],  # deprecated
                }
            )

        elif comp_type == "BUTTONS":
            for idx, button in enumerate(component["buttons"]):
                button_type = button["type"].upper()
                button_name = f"button.{idx}"
                button_text = button.get("text", "")

                if button_type == "QUICK_REPLY":
                    button_vars = add_variables(_extract_variables(button_text), "text")
                    components.append(
                        {
                            "type": "button/quick_reply",
                            "name": button_name,
                            "content": button_text,
                            "variables": button_vars,
                            "params": [{"type": "text"} for v in button_vars],  # deprecated
                        }
                    )

                elif button_type == "URL":
                    button_url = button.get("url", "")
                    button_vars = add_variables(_extract_variables(button_url), "text")
                    components.append(
                        {
                            "type": "button/url",
                            "name": button_name,
                            "content": button_url,
                            "display": button_text,
                            "variables": button_vars,
                            "params": [{"type": "text"} for v in button_vars],  # deprecated
                        }
                    )

                elif button_type == "PHONE_NUMBER":
                    phone_number = button.get("phone_number", "")
                    components.append(
                        {
                            "type": "button/phone_number",
                            "name": button_name,
                            "content": phone_number,
                            "display": button_text,
                            "variables": {},
                            "params": [],  # deprecated
                        }
                    )

                else:
                    supported = False
        else:
            supported = False

    return components, variables, supported


def parse_language(lang) -> str:
    """
    Converts a WhatsApp language code which can be alpha2 ('en') or alpha2_country ('en_US') or alpha3 ('fil')
    to our locale format ('eng' or 'eng-US').
    """
    language, country = lang.split("_") if "_" in lang else [lang, None]
    if len(language) == 2:
        language = alpha2_to_alpha3(language)

    return f"{language}-{country}" if country else language
