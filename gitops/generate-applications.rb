#!/usr/bin/env ruby
# Generates Argo CD Applications from the releases declared in helmfile.yaml.

require "yaml"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
HELMFILE = YAML.safe_load(File.read(File.join(ROOT, "helmfile.yaml")), [], [], true)
GIT_REPO = ENV.fetch("GIT_REPO", "https://github.com/vitorbiazotti/proxmox-talos-main.git")
GIT_REVISION = ENV.fetch("GIT_REVISION", "main")
OUTPUT = File.join(__dir__, "applications", "platform-addons.yaml")

repositories = HELMFILE.fetch("repositories").to_h { |repo| [repo.fetch("name"), repo.fetch("url")] }
releases = HELMFILE.fetch("releases")
release_by_key = releases.to_h { |release| ["#{release.fetch("namespace")}/#{release.fetch("name")}", release] }

def dependency_depth(release, release_by_key, memo = {})
  key = "#{release.fetch("namespace")}/#{release.fetch("name")}" 
  return memo[key] if memo.key?(key)

  dependencies = Array(release["needs"]).map { |need| release_by_key[need] }.compact
  memo[key] = dependencies.empty? ? 0 : dependencies.map { |dep| dependency_depth(dep, release_by_key, memo) }.max + 1
end

def helm_values(release)
  Array(release["values"]).each_with_object({}) do |entry, result|
    result.merge!(entry) if entry.is_a?(Hash)
  end
end

documents = []

{
  "local-path-provisioner" => "privileged",
  "metallb-system" => "privileged",
  "monitoring" => "privileged"
}.each do |namespace, level|
  documents << {
    "apiVersion" => "v1",
    "kind" => "Namespace",
    "metadata" => {
      "name" => namespace,
      "annotations" => { "argocd.argoproj.io/sync-wave" => "-100" },
      "labels" => {
        "pod-security.kubernetes.io/enforce" => level,
        "pod-security.kubernetes.io/audit" => level,
        "pod-security.kubernetes.io/warn" => level
      }
    }
  }
end

releases.each do |release|
  chart = release.fetch("chart")
  namespace = release.fetch("namespace")
  name = release.fetch("name")
  values = helm_values(release)
  depth = dependency_depth(release, release_by_key)

  source = if chart.start_with?("./")
    {
      "repoURL" => GIT_REPO,
      "targetRevision" => GIT_REVISION,
      "path" => chart.delete_prefix("./"),
      "helm" => { "releaseName" => name }
    }
  else
    repository_name, chart_name = chart.split("/", 2)
    {
      "repoURL" => repositories.fetch(repository_name),
      "chart" => chart_name,
      "targetRevision" => release.fetch("version").to_s,
      "helm" => { "releaseName" => name }
    }
  end

  source["helm"]["values"] = YAML.dump(values).sub(/\A---\s*\n/, "") unless values.empty?

  application = {
    "apiVersion" => "argoproj.io/v1alpha1",
    "kind" => "Application",
    "metadata" => {
      "name" => name,
      "namespace" => "argocd",
      "annotations" => { "argocd.argoproj.io/sync-wave" => depth.to_s }
    },
    "spec" => {
      "project" => "default",
      "source" => source,
      "destination" => {
        "server" => "https://kubernetes.default.svc",
        "namespace" => namespace
      },
      "syncPolicy" => {
        "automated" => { "prune" => true, "selfHeal" => true },
        "syncOptions" => ["CreateNamespace=true", "ServerSideApply=true"]
      }
    }
  }

  documents << application
end

FileUtils.mkdir_p(File.dirname(OUTPUT))
File.write(OUTPUT, documents.map { |document| YAML.dump(document) }.join)
puts "Generated #{releases.length} Argo CD Applications in #{OUTPUT}"
