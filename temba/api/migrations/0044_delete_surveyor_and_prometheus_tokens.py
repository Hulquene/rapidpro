# Generated by Django 5.0.8 on 2024-08-08 23:34

from django.db import migrations


def delete_surveyor_and_prometheus_tokens(apps, schema_editor):
    APIToken = apps.get_model("api", "APIToken")
    Group = apps.get_model("auth", "Group")

    surveyors = Group.objects.filter(name="Surveyors").first()
    prometheus = Group.objects.filter(name="Prometheus").first()
    num_surveyors, num_prometheus = 0, 0

    if surveyors:
        for token in APIToken.objects.filter(role=surveyors):
            token.delete()
            num_surveyors += 1

    if prometheus:
        for token in APIToken.objects.filter(role=prometheus):
            token.delete()
            num_prometheus += 1

    if num_surveyors or num_prometheus:
        print(f"Deleted {num_surveyors} surveyor tokens and {num_prometheus} prometheus tokens.")


class Migration(migrations.Migration):

    dependencies = [("api", "0043_squashed")]

    operations = [migrations.RunPython(delete_surveyor_and_prometheus_tokens, migrations.RunPython.noop)]
