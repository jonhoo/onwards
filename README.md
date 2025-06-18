Onwards is my attempt at building a re-usable URL shortener for links
that I'll put in my book, [Rust for Rustaceans][r4r]. I didn't want to
pay a monthly fee to a URL shortener with support for custom domains,
not because the additional data analytics they give you and such
wouldn't be nice, but because $8+/month seemed excessive to agree to pay
in perpetuity.

So, onwards was born. It is hosted using an [AWS Lambda][lambda],
meaning there is no always-on server cost. It keeps no access statistics
and hard-codes the shortlinks in the binary, so there is no storage
cost. It uses [AWS CloudFront][cf] for caching, so even if there are
floods of traffic, the incurred cost is minimal.

## How much does it cost?

I haven't published the version of the book that has these links yet,
but will update this with my final bill once I do. My expectation is
about $1/month for the traffic, with half of that going to the fixed
cost of Route 53, AWS' DNS provider. Then there's Terraform for managing
the deployment when I push new changes and such, which will probably
even out at about $2/month (which is really quite wild). Meaning in
total I pay $3/month, with full control over the shortening (and no
limits!).

If anyone has ideas for reducing this cost further _without affecting
the stable-state workflow_, I'd love to hear them.

[r4r]: https://rust-for-rustaceans.com/
[lambda]: https://aws.amazon.com/lambda/
[cf]: https://aws.amazon.com/cloudfront/

## How do I use it?

It's a bit of a process to get the infrastructure set up, but once it's
set up, changing the short links is one GitHub MR that you hit merge on.
In other words, only really headache up front, and then you don't have
to touch it. If anyone has ideas for removing steps from this _without
affecting the stable-state workflow_, I'd love to hear them.

Here's what you do:

1. Fork this repo
1. Sign up for [Terraform Cloud](https://app.terraform.io/public/signup/account)
1. [Create a Terraform organization](https://app.terraform.io/app/organizations/new)
1. Create a workspace in that organization called "onwards"
1. Go to Settings -> Plan & Billing -> pick the "Standard" plan
1. Go to Settings -> Teams, and create two teams, "ci-plan" and
   "ci-apply". Both should have "view" access to projects and
   workspaces. "ci-apply" should additionally have "Manage run tasks".
1. Open the "onwards" Terraform workspace, go to Settings -> General,
   and set the "Terraform Working Directory" to "infra".
1. Go to Settings -> Team Access, and add ci-plan with "Plan"
   privileges, and ci-apply with "Write" privileges.
1. Go to your onwards fork on GitHub -> Settings -> Environments
1. Add (or edit) the environment called "prod". Set it to target the
   `main` branch.
1. In Terraform, go back to the organization, then to Settings -> API
   tokens -> Team Tokens, and create a new token for the ci-apply team
   with no expiry. Copy the token it gives you.
1. In GitHub, hit "Add environment secret", put in the name
    `TF_API_TOKEN` and paste the Terraform token as the value.
1. In GitHub, go to Secrets and variables -> Actions -> Variables.
1. In Terraform, under "Team Tokens", create a new token for the
   ci-plan team (again with no expiry). Copy the token it gives you.
1. In GitHub, hit "New repository variable", name it
   `TF_API_PLAN_TOKEN` and paste the token from Terraform.
1. Add two more repository variables:
   - `TF_CLOUD_ORGANIZATION`: the name of the Terraform organization you created.
   - `TF_WORKSPACE`: the name of the Terraform workspace you created.
1. Sign up for an AWS account if you haven't already, then go to [AWS
   Organizations](https://us-east-1.console.aws.amazon.com/organizations/v2/home/accounts)
   and hit "Add an AWS account". Create a new one, and give it whatever
   name + email you want. I recommend keeping the IAM role name the
   default.
1. Once created, copy the account number of the newly created AWS
   organization account, hit the user dropdown top left of the AWS
   console, and select "Switch role". Input the account ID for the newly
   created account, `OrganizationAccountAccessRole` as the IAM role
   name, and hit the "Switch Role" button.
1. Follow Terraform's guide to [connecting with AWS][tf-aws] up until
   (but not including) the "Configure HCP Terraform" section. For
   `RUN_PHASE` use `*` (see the little box), and give it the
   `AdministratorAccess` permission (we'll reduce this for "plan" in a
   second). Name the role `tfc-apply-role`.
1. In Terraform, open the "onwards" workspace, go to Settings ->
   Variables, and configure the following Terraform (not environment)
   variables:
   - `aws_region`: where you'd like the service to be hosted.
   - `domain`: the domain you want to use for forwarding.
   - `tfc_organization_name`: the name of the Terraform organization you created (yes, again).
   - `tfc_workspaec_name`: the name of the Terraform workspace you created (yes, again).
1. Then, configure the following environment (not Terraform) variables
   in the same place, using the AWS account number instead of `XYZ`:
   - `TFC_AWS_APPLY_ROLE_ARN`: `arn:aws:iam::XYZ:role/tfc-apply-role`
   - `TFC_AWS_PLAN_ROLE_ARN`: `arn:aws:iam::XYZ:role/tfc-apply-role`
     (yes, that's `apply` again; for now).
   - `TFC_AWS_PROVIDER_AUTH`: `true`
1. Next, cd to `onwards` and run
   ```console
   terraform -chdir=infra apply
   ```
   After the "Plan" step finishes, you'll have to confirm that you want
   to apply the changes (type "yes" and hit enter). Some of the steps
   will fail (specifically "tfc_provider" and "tfe_workspace". That's
   fine. For the TLS certificate creation to finish successfully, we
   also now need to set up your name servers:
1. In the AWS console, go to Route 53 -> Hosted zones, open your domain,
   expand the "Hosted zone details" box. You'll want to take all the
   domains listed under "Name servers" and make them be the name servers
   set for your domain with your domain registrar. Do that now.
   Eventually, the Terraform apply should finally finish.
1. Now, we need to tell Terraform about the resources we pre-created.
   This part is a little annoying, because the `terraform import`
   process runs _locally_. So, you'll want to set up the AWS CLI
   locally, and then in your `~/.aws/config`, add a stanza like
   ```ini
   [profile onwards]
   role_arn = arn:aws:iam::XYZ:role/OrganizationAccountAccessRole
   source_profile = default
   ```
   To test it, see that you can run:
   ```console
   env AWS_PROFILE=onwards aws account get-account-information
   ```
   Then, _comment out_ the `tfc_aws_dynamic_credentials` variable block
   in `infra/main.tf`. Also comment out each instance of
   ```ini
   shared_config_files =
   ```
   and put the following just after each one (replacing `$HOME` with
   the path to your home directory):
   ```ini
   shared_credentials_files = ["$HOME/.aws/credentials"]
   ```
1. In the AWS console, go to IAM -> Identity providers, and open the
   app.terraform.io provider you created earlier. Copy its ARN (top
   right), then run the following command, filling in the `$` values
   from your Terraform workspace variables:
   ```console
   env AWS_PROFILE=onwards \
     terraform -chdir=infra import \
     -var aws_region=$aws_region -var domain=$domain -var tfc_organization_name=$tfc_organization_name \
     aws_iam_openid_connect_provider.tfc_provider \
     $copied_arn
   ```
1. Then run (still substituting `$` values):
   ```console
   env AWS_PROFILE=onwards \
     terraform -chdir=infra import \
     -var aws_region=$aws_region -var domain=$domain -var tfc_organization_name=$tfc_organization_name \
     aws_iam_role.tfc_apply tfc-apply-role
   ```
1. In Terraform, go to the onwards workspace and copy the "ID" near the
   top of the page. Then run (still substituting `$` values):
   ```console
   env AWS_PROFILE=onwards \
     terraform -chdir=infra import \
     -var aws_region=$aws_region -var domain=$domain -var tfc_organization_name=$tfc_organization_name \
     tfe_workspace.onwards \
     $copied_id
   ```
1. Now, undo those local changes to `infra/main.tf`, and run
   ```console
   terraform -chdir=infra apply
   ```
   This time, it should complete successfully!
1. This will have created all the various AWS bits and bops, including
   the `tfc-plan-role`. Go ahead and change `TFC_AWS_PLAN_ROLE_ARN` to
   `arn:aws:iam::XYZ:role/tfc-plan-role` now.
1. Open `$yourdomain/about` and see that it redirects to the onwards
   GitHub project. Congratulations -- setup is now done! Let's check
   that adding some links works.
1. Open an MR against your fork of the repo where you edit `src/lib.rs`
   to add additional short-links. Once CI passes, merge the MR.
1. Open the CI for the `main` branch; there should be a job running
   named "Terraform Cloud Apply Run / Terraform Apply". It should
   succeed. When it does:
1. Test your new short-link! The process for adding more links is the
   same: push a commit that changes `src/lib.rs` — that's it. Even the
   MR is optional.

Now, if you do end up using this "for real", please let me know, because
it makes me happy!

Also, you may want to merge from this repo occasionally in case I've
made improvements to the system. I don't anticipate adding any features
really, though may improve the infrastructure setup (mainly to make it
cheaper).

[tf-aws]: https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration
