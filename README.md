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
floods of traffic, the incurred cost is minimal. And, because it's all
stateless and serverless, it should scale to basically any user load.

## How much does it cost?

I haven't published the version of the book that has these links yet,
but will update this with my final bill once I do. My expectation is
about $1/month for the traffic, with half of that going to the fixed
cost of Route 53, AWS' DNS provider. Meaning in total I pay $1/month,
with full control over the shortening (and no limits!).

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
1. Fork this repo
1. Go to your onwards fork on GitHub -> Settings -> Environments
1. Add (or edit) the environment called "prod". Set it to target the
   `main` branch.
1. Next, go to Secrets and variables -> Actions -> Variables. Use "New
   repository variable" to add the following variables:
   - `AWS_REGION`: the AWS region you'd like to host the service in
   - `DOMAIN`: the domain you want to host the service under
   - `AWS_PLAN_ROLE`: `arn:aws:iam::$THE_AWS_ACCOUNT_NUMBER_FROM_ABOVE:role/tf-plan-role`
   - `AWS_APPLY_ROLE`: `arn:aws:iam::$THE_AWS_ACCOUNT_NUMBER_FROM_ABOVE:role/tf-apply-role`
1. Now, we need to make it possible to run Terraform locally for the
   first apply, which will also set up the permissions needed for GitHub
   Actions to run plan and apply. You'll want to set up the AWS CLI
   locally, and then in your `~/.aws/config`, add a stanza like
   ```ini
   [profile onwards]
   role_arn = arn:aws:iam::$THE_AWS_ACCOUNT_NUMBER_FROM_ABOVE:role/OrganizationAccountAccessRole
   source_profile = default
   ```
   To test it, see that you can run:
   ```console
   env AWS_PROFILE=onwards aws account get-account-information
   ```
1. We also need to manually set up the S3 bucket that Terraform's state
   will be kept in. Luckily, we only have to do so once. You can do that
   by running the following commands, substituting in `$DOMAIN` and
   `$AWS_REGION`:
   ```console
   env AWS_PROFILE=onwards aws s3api create-bucket --bucket onwards.$DOMAIN.terraform --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
   env AWS_PROFILE=onwards aws s3api put-bucket-versioning --bucket onwards.$DOMAIN.terraform --versioning-configuration Status=Enabled
   ```
   Once that's done, open `infra/main.tf` and look for the `CHANGEME
   NOTE`. Update the bucket name and region there to match what you gave
   in the command above.
1. Now, we must build the main binary so it can be uploaded to AWS. To
   do so, [install
   cargo-lambda](https://www.cargo-lambda.info/guide/getting-started.html),
   and then in your checkout of onwards, run
   ```console
   cargo lambda build --release --arm64
   ```
1. Finally, we're ready to set up all the infrastructure! `cd infra/`
   and run:
   ```console
   terraform init
   terraform apply
   ```
   It will prompt you for three values:
   - `aws_region` and `domain`, which you should provide the same value
     as you did for the GitHub variables.
   - `github_repo`, which you should set to the GitHub repository of
     your fork (e.g., `jonhoo/onwards`).
   After the "Plan" step finishes, you'll have to confirm that you want
   to apply the changes (type "yes" and hit enter). The TLS certificate
   creation step will hang until we finish domain setup, so leave the
   hanging apply open while we set up the name servers:
1. In the AWS console, go to Route 53 -> Hosted zones, open your domain,
   expand the "Hosted zone details" box. You'll want to take all the
   domains listed under "Name servers" and make them be the name servers
   set for your domain with your domain registrar. Do that now.
   Eventually, the Terraform apply should finally finish successfully.
1. Commit your change to `infra/main.tf` and push! You should be able to
   go to GitHub and see the terraform/apply step succeed with only
   marginal changes (like the hash of the lambda binary changing since
   it's now built on CI).
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
1. (optional) If you want email through your domain, it's already set up
   to use https://improvmx.com/ out of the box, which is free for a
   single domain! All you should need to do is make an account and input
   your domain, and all should be green. If you want to do email through
   another service, you'll have to modify `infra/domain.tf`.

Now, if you do end up using this "for real", please let me know, because
it makes me happy!

Also, you may want to merge from this repo occasionally in case I've
made improvements to the system. I don't anticipate adding any features
really, though may improve the infrastructure setup (mainly to make it
cheaper).

[tf-aws]: https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration
