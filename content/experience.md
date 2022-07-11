+++
title="Experience"
description="List of some of the more notable projects I've been involved with over the years, as well as a description of my responsibilities within the project."
+++

Below you'll find a list of some of the more notable projects I've been involved with over the years,
as well as a description of my responsibilities within the project.

---

## Terraform-based EKS deployment for Startup
This project was two-fold, and involved designing and deploying an AWS EKS setup for the customer, 
which allowed them to easily deploy so-called "ringfenced" namespaces to specific AWS regions.

The **Core EKS Setup** involved provisisoning a "batteries included" EKS cluster with an OpenID Connect
provider configuration to link in-cluster Service Accounts to AWS IAM Roles, and a completely automated Ingress-stack, made up of:
* [AWS ALB Controller](https://github.com/kubernetes-sigs/aws-load-balancer-controller) for automatic Load Balancer provisioning when Ingress-resources are deployed,
* [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) for configuring Route53 domain records according to Ingress resource definitions.
* [cert-manager](https://cert-manager.io/v0.14-docs/installation/kubernetes/) controller for automatic certificate acquisition and renewal, again based on Ingress definitions.

All of which was deployed using the Helm Provider for Terraform.

In addition to this, I also delivered a **"Ringfence" Terraform Module** which could be invoked in order to produce
A completely segregated persistence suite (S3, RDS, CloudFront) within any region, and tie them to a specific
namespace within the Kubernetes cluster, using the aforementioned OIDC Service Account/AWS IAM mapping.

This enabled the customer to offer complete segregation of at-rest data storage to their own customers,
in accordance with whatever data-locality compliance requirements they were subject to, while minimizing the
blast radius, even for customers who resided within the same region.

This design meant that deploying to specific regions as customers were onboarded was more or less
"Plug & Play" since IAM-based access, DNS, Certificate management, and so on was entirely automated, meaning
deploying their containers to a new namespace "just works", at least as far as the infrastructure is concerned.

**Technologies** 
[AWS EKS](https://aws.amazon.com/eks/),
[AWS VPC](https://aws.amazon.com/vpc/),
[AWS PrivateLink](https://aws.amazon.com/privatelink/),
[AWS S3](https://aws.amazon.com/s3/),
[Terraform](https://www.terraform.io/),
[Helm](https://helm.sh/docs/topics/charts/),
[OpenID Connect](https://openid.net/connect/).

**Customers** SaaS Startup in the child-care space.

**Duration** 2 months

---

## AWS Control Tower & SSO using Google Workspace
For this project, I deployed and configured an AWS Control Tower account structure which could then be
used to migrate the existing 10-15 AWS accounts used for both internal and external customers, which 
we had access to.

For internal accounts, as well as external accounts owned by customers who had agreed to consolidated
billing, the process involved preparing their accounts for enrollment, enrolling them, and cleaning up
any leftover IAM users and groups which were no longer required.

For external accounts belonging to customers who managed billing for themselves, enrolling them in
Control Tower was not an option, since doing so requires all the accounts to belong to the same
AWS Organization, which implies consolidated billing. For these accounts, simple AWS SSO mapping using
SAML and client-side identity providers were configured instead.

On top of this, automatic user and group synchronization from the Google Workspace account which acted
as the source of truth as far as employee access was concerned, was set up using an [AWS Labs lambda
solution](https://github.com/awslabs/ssosync).


**Technologies**
[AWS Control Tower](https://aws.amazon.com/controltower/),
[AWS Organizations](https://aws.amazon.com/organizations/),
[AWS SSO](https://aws.amazon.com/single-sign-on/),
[Terraform](https://www.terraform.io/),
[SAML](https://en.wikipedia.org/wiki/Security_Assertion_Markup_Language),
[Google Workspace](https://workspace.google.com/).

**Customers** Creative Bureau

**Duration** 4 months

---

## Cross-account AWS CloudWatch Logging (proof of concept only)

Although never implemented, this project involved designing a process for aggregating CloudWatch logs
produced by Java applications sent from a third-party AWS account that the customer did not have access
to, in a minimally invasive way.
    
The third party vendor did not allow any kind of access to the source AWS Account by the customer, and were
themselves not interested in producing an AWS-native solution, so a colleague and I were tasked with 
designing a process by which logs could be extracted from the vendor's EC2 hosts, requiring minimal
configuration on their part.

Using CloudWatch Agent with a configuration provided by us, submitting logs across AWS account boundaries
to a CloudWatch Log Group within the customer's Log Archive account, using very strict IAM permissions
granted to the vendor's account for that specific log group, allowed the logs to be submitted without
unnecessary exposure from either side.

**Technologies**
[AWS IAM](https://aws.amazon.com/iam/),
[AWS VPC](https://aws.amazon.com/vpc/),
[AWS PrivateLink](https://aws.amazon.com/privatelink/),
[AWS S3](https://aws.amazon.com/s3/),
[AWS CloudWatch](https://aws.amazon.com/cloudwatch/),
[Terraform](https://www.terraform.io/).

**Customers** Large financial institution

**Duration** 1 month

---

## On-premise Kubernetes deployment for hosting wide range of customer web applications
While employed at a creative bureau as a DevOps Engineer I identified Kubernetes as a possible solution
to an organizational hurdle within the company.

With around 60 developers spread across multiple departments and geographic locations, and a completely
bespoke deployment pipeline based on Ansible with a thin wrapper around this, educating new developers
as well as troubleshooting deployment issues was a massive time-sink for the Operations and Development
departments. The nature of the deployment system meant that knowledge about how it actually worked
"under the hood" was held entirely by a few employees who had been around when it was first implemented.

I proposed looking into Kubernetes, or at least containerization, initially as a means of standardization
across departments. Familiarity with Docker was fairly common, and the Operations department, of which I
was part, had previous experience with managing Kubernetes cluster infrastructure, although not so much
running things inside of them.

Apart from standardizing around a known and widely adopted technology to cut down on internal
education, the workloads deployed to this private cloud lent itself very well to Kubernetes. The vast
majority of the around ~400 applications were WordPress or Drupal with some customization and then a
few completely custom applications developed either in PHP or Go.

Some of the benefits I identified and outlined when proposing this venture was:
* Standardization means you can google most of your questions and lighten education load on
  senior developers and operations, as well as grant access to profesionally developed courses
  as part of onboarding.

* Increased isolation between processes. While not a perfect solution, Kubernetes provides some
  isolation between containers if configured properly, and could prevent widespread compromise
  in the event a reverse shell was installed by way of a vulnerable WordPress plugin or the like.

* Advanced deployment strategies such as canary or blue/green deployments. The system in place
  was an all-or-nothing deployment solution, which meant that apart from deploying to a test
  environment (which differed from the production environment in some ways) first, there was
  no way of verifying a build prior to deployment.

* Automating menial tasks such as roll-backs of deployments, migrating production data into 
  test environments, and configuring database credentials, could be automated by controllers
  written and managed by the Operations team. One such controller was developed in __Rust__ by me as
  part of the trials of this solution, and involved defining a Database Custom Resource Definition,
  which was then applied as part of the application deployment pipeline, and ensured that the
  required database and credentials were configured in the appropriate multi-tenant MySQL instances.

The project enjoyed some success, but was stalled by a combination of high-level focus changes
within the company away from internal on-premise hosting and onto consultancy contracting, the linux
[kernel bug](https://github.com/kubernetes/kubernetes/issues/67577) which impacted CPU-limited pods, 
even if plenty of compute was available, which we observed but were unable to diagnose, as well as
the unfortunate resignation of the Operations team lead, who had been a big advocate of the project.
  
**Technologies**
[Kubernetes](https://kubernetes.io/),
[HashiCorp Packer](https://www.packer.io/),
[GitLab CI/CD](https://docs.gitlab.com/ee/ci/),
[VMWare vSphere](https://www.vmware.com/products/vsphere.html).


**Customers** Creative bureau

**Duration** 1.5 years

---

## Migrating web application to AWS ECS using Terraform
This project involved __Containerizing__ and lifting an existing PHP website hosted directly
on EC2 instances into ECS, while moving to AWS-native services for databases (RDS) and
session caching (AWS ElastiCache).

In collaboration wih another DevOps Engineer, we architected the new ECS-based solution 
with help from someone with prior knowledge of the existing setup, and then provisioned
the infrastructure using Terraform, as well as the deployment pipeline for the GitHub-hosted
codebase.

The software developers on the project were responsible for producing a Dockerfile we could build.
while we managed the deployment of RDS, ElastiCache, Secrets Manager, ECS Tasks, Services, 
secret mounting, and of course very granular IAM Roles for each deployment environment.

The project also involved educating the developers, because of a lack of familiarity with
container-based build pipelines and deployments, especially to a service like ECS Fargate
where conventional debugging tools like accessing the server and poking around is not a
possibility.

**Technologies** 
[AWS Fargate (ECS)](https://aws.amazon.com/fargate/),
[AWS IAM](https://aws.amazon.com/iam/),
[AWS ElastiCache](https://aws.amazon.com/elasticache/),
[AWS RDS](https://aws.amazon.com/rds/),
[AWS Secrets Management](https://aws.amazon.com/secrets-manager/),
[Terraform](https://www.terraform.io/),
[GitHub Actions (CI/CD)](https://github.com/features/actions).

**Customers** Grocery Store chain.

**Duration** 5 months

---

## Ansible-defined configuration management for webhosting
During my employment at a creative burau I helped improve and harden Ansible-managed web host
configuration which was responsible for routing, caching and serving multiple 
interactive websites across on-prem (VMWare vSphere) and AWS EC2 instances.

The entire project was set up based on the principle of __Desired State Specification__,
whereby the configuration of the entire fleet was defined ahead of time, and the
playbooks were designed to correct any detected drift on the managed servers,
which was common because of customers' access to the managed machines.

When customers would develop new functionality or required modifications to the
routing or caching setups, they would either produce the changes themselves on
the machines, or describe them to us, at which point we would backport the changes,
until our Ansible configuration matched reality.

**Technologies**
[AWS EC2](https://aws.amazon.com/ec2/), 
[Ansible](https://www.ansible.com/),
[Nginx](https://www.nginx.com/),
[Varnish](https://varnish-cache.org/),
[HAProxy](https://www.haproxy.org/),
[VMWare vSphere](https://www.vmware.com/products/vsphere.html).

**Customers** Danish Institutions, Grocery Store chain, Real Estate company, and more.

**Duration** 2 years