# Copyright 2020 Open Source Robotics Foundation, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import os
import sys
import time

from pulpcore.client import pulp_rpm, pulpcore
from urllib3.exceptions import MaxRetryError


class PulpTaskPoller:

    def __init__(self, pulp_configuration, timeout):
        client = pulpcore.ApiClient(pulp_configuration)
        self._tasks_api = pulpcore.TasksApi(client)
        self._timeout = timeout

    def wait_for_task(self, task_href):
        task = self._tasks_api.read(task_href)

        print("Waiting for task '%s'..." %
              (self._tasks_api.api_client.configuration.host + task.pulp_href))

        timeout = self._timeout
        while task.state != 'completed':
            if task.state in ['failed', 'canceled']:
                raise Exception(
                    "Pulp task '%s' did not complete (%s)" % (task.pulp_href, task.state))
            time.sleep(0.5)
            timeout -= 0.5
            if timeout <= 0:
                task_cancel = pulpcore.TaskCancel('canceled')
                task = self._tasks_api.tasks_cancel(task.pulp_href, task_cancel)
                if task.state != 'completed':
                    raise Exception(
                        "Pulp task '%s' did not complete (timed out)" % task.pulp_href)

            task = self._tasks_api.read(task.pulp_href)

        print('...done.')
        return task


def main(argv=sys.argv[1:]):
    parser = argparse.ArgumentParser(
        description='Ensure RPM repositories exist in pulp')
    parser.add_argument(
        '--pulp-base-url',
        default=os.environ.get('PULP_BASE_URL'), required=not bool(os.environ.get('PULP_BASE_URL')),
        help='URL of the pulp API endpoint')
    parser.add_argument(
        '--pulp-username',
        default=os.environ.get('PULP_USERNAME'), required=not bool(os.environ.get('PULP_USERNAME')),
        help='Username used to access the pulp API endpoint')
    parser.add_argument(
        '--pulp-password',
        default=os.environ.get('PULP_PASSWORD'), required=not bool(os.environ.get('PULP_PASSWORD')),
        help='Password used to access the pulp API endpoint')
    parser.add_argument(
        '--pulp-task-timeout',
        default=60.0,
        help='Duration to wait (in seconds) for a pulp task to complete')
    parser.add_argument(
        '--signing-service-name',
        help='Name of the pulp signing service to use with the repository')
    parser.add_argument(
        '--upstream-repository',
        help='URL of an upstream repository - a pulp remote will be created with the same name '
             'as this repository and associate it with this repository')
    parser.add_argument(
        'repository_name',
        help='Name of the repository to be created')
    parser.add_argument(
        'distribution_endpoint', nargs='+',
        help='One or more URL endpoints where the repository should be served')
    args = parser.parse_args(argv)

    pulp_config = pulp_rpm.Configuration(
        args.pulp_base_url, username=args.pulp_username,
        password=args.pulp_password)

    # https://pulp.plan.io/issues/5932
    pulp_config.safe_chars_for_path_param = '/'

    # Wait for pulp to become available
    pulp_client = pulpcore.ApiClient(pulp_config)
    pulp_status_api = pulpcore.StatusApi(pulp_client)

    status_timeout = args.pulp_task_timeout
    pulp_is_ready = False
    print('Checking status of pulpcore...')
    while not pulp_is_ready:
        try:
            pulp_status = pulp_status_api.status_read()
            pulp_is_ready = pulp_status.online_workers and \
                pulp_status.online_content_apps and \
                pulp_status.database_connection.connected and \
                pulp_status.redis_connection.connected
            if pulp_is_ready:
                continue
            else:
                print('Pulpcore is not ready. Waiting %d more seconds...' % status_timeout)
        except MaxRetryError:
            print('Pulpcore connection failed. Waiting %d more seconds...' % status_timeout)

        time.sleep(1)
        status_timeout -= 1

        if status_timeout <= 0:
            break

    if pulp_is_ready:
        print('Connected - pulpcore is ready.')
    else:
        print('Pulpcore is not ready or could not be reached. Exiting.')
        return 1

    pulp_rpm_client = pulp_rpm.ApiClient(pulp_config)
    pulp_distributions_api = pulp_rpm.DistributionsRpmApi(pulp_rpm_client)
    pulp_publications_api = pulp_rpm.PublicationsRpmApi(pulp_rpm_client)
    pulp_repos_api = pulp_rpm.RepositoriesRpmApi(pulp_rpm_client)

    pulp_task_poller = PulpTaskPoller(pulp_config, args.pulp_task_timeout)

    metadata_signing_service = None
    if args.signing_service_name:
        pulp_signing_api = pulpcore.SigningServicesApi(pulp_client)
        signing_services = pulp_signing_api.list(name=args.signing_service_name)
        if not signing_services.results:
            print("Invalid signing service name '%s'." % args.signing_service_name)
            return 1
        metadata_signing_service = signing_services.results[0].pulp_href
        print("Using signing service '%s' (%s)" % (signing_services.results[0].name, metadata_signing_service))

    remote_href = None
    if args.upstream_repository:
        pulp_remotes_api = pulp_rpm.RemotesRpmApi(pulp_rpm_client)
        remotes = pulp_remotes_api.list(name=args.repository_name)
        if remotes.results:
            remote = remotes.results[0]
            if remote.url != args.upstream_repository:
                remote.url = args.upstream_repository
                pulp_remotes_api.partial_update(remote.pulp_href, remote)
        else:
            new_remote = pulp_rpm.RpmRpmRemote(
                name=args.repository_name, url=args.upstream_repository)
            print("Creating remote '%s'" % new_remote.name)
            remote = pulp_remotes_api.create(new_remote)
        print("Using remote '%s' (%s)" % (remote.name, remote.pulp_href))
        remote_href = remote.pulp_href

    # Check if the repository exists. If not, create it.
    repositories = pulp_repos_api.list(name=args.repository_name)
    republish = False
    if repositories.results:
        repository = repositories.results[0]
        repo_update = False

        if (metadata_signing_service or '') != (repository.metadata_signing_service or ''):
            repository.metadata_signing_service = metadata_signing_service or ''
            repo_update = True
            republish = True

        if (remote_href or '') != (repository.remote or ''):
            repository.remote = remote_href or ''
            repo_update = True

        if repo_update:
            pulp_repos_api.partial_update(repository.pulp_href, repository)
    else:
        new_repository = pulp_rpm.RpmRpmRepository(
            name=args.repository_name, metadata_signing_service=metadata_signing_service,
            remote=remote_href)

        print("Creating repository '%s'" % new_repository.name)
        repository = pulp_repos_api.create(new_repository)

    print("Using repository '%s' (%s)" % (repository.name, repository.pulp_href))

    # Keep track of what publication to use if one of the endpoints is lacking
    default_publication = None
    for endpoint in args.distribution_endpoint:

        # Check if a distribution exists. If not, create one.
        distributions = pulp_distributions_api.list(base_path=endpoint)
        if distributions.results:
            distribution = distributions.results[0]
        else:
            new_distribution = pulp_rpm.RpmRpmDistribution(
                name=endpoint, base_path=endpoint, publication=default_publication)

            print("Creating distribution at endpoint '%s'" % endpoint)
            distribution_task_href = pulp_distributions_api.create(new_distribution).task
            distribution_task = pulp_task_poller.wait_for_task(distribution_task_href)
            distribution_href = distribution_task.created_resources[0]
            distribution = pulp_distributions_api.read(distribution_href)

        print("Using distribution at '%s' (%s)" % (distribution.base_path, distribution.pulp_href))

        # Check if a publication backs the distribution. If not, set one.
        redistribute = False
        if not distribution.publication:
            # If we don't have a default publication, create one.
            if not default_publication:
                new_publication = pulp_rpm.RpmRpmPublication(
                    repository_version=repository.latest_version_href)

                print("Creating publication for repository '%s'" % repository.name)
                publication_task_href = pulp_publications_api.create(new_publication).task
                publication_task = pulp_task_poller.wait_for_task(publication_task_href)
                default_publication = publication_task.created_resources[0]

            distribution.publication = default_publication
            redistribute = True
        elif republish:
            publication = pulp_publications_api.read(distribution.publication)

            new_publication = pulp_rpm.RpmRpmPublication(
                repository_version=publication.repository_version)

            print("Creating publication for repository '%s'" % repository.name)
            publication_task_href = pulp_publications_api.create(new_publication).task
            publication_task = pulp_task_poller.wait_for_task(publication_task_href)

            distribution.publication = publication_task.created_resources[0]
            redistribute = True

        if redistribute:
            print("Updating distribution at '%s' to use '%s'" % (
                distribution.base_path, distribution.publication))

            distribution_task_href = pulp_distributions_api.partial_update(
                distribution.pulp_href, distribution).task
            pulp_task_poller.wait_for_task(distribution_task_href)


if __name__ == '__main__':
    sys.exit(main())
