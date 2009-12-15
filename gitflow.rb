Capistrano::Configuration.instance(true).load do
    before "deploy:update_code", "gitflow:calculate_tag"
    namespace :gitflow do
        def last_tag_matching(matchTag)
            lastTag = nil

            allTagsMatching = `git tag -l '#{matchTag}*'`
            allTagsMatching = allTagsMatching.split
            natcmpSrc = File.join(File.dirname(__FILE__), '/natcmp.rb')
            require natcmpSrc
            allTagsMatching.sort! do |a,b|
                String.natcmp(b,a,true)
            end
            
            if allTagsMatching.length > 0
                lastTag = allTagsMatching[0]
            end
            return lastTag
        end

        def last_staging_tag()
            return last_tag_matching('staging-')
        end

        def last_production_tag()
            return last_tag_matching('production-')
        end

        desc "Calculate the tag to deploy"
        task :calculate_tag do
            # make sure we have any other deployment tags that have been pushed by others so our auto-increment code doesn't create conflicting tags
            `git fetch`

            tagMethod = "tag_#{stage}"
            send tagMethod

            # push tags and latest code
            system 'git push'
            if $? != 0
                raise "git push failed"
            end
            system 'git push --tags'
            if $? != 0
                raise "git push --tags failed"
            end
        end

        desc "Show log between most recent staging tag (or given tag=XXX) and last production release."
        task :update_log do
            fromTag = nil
            toTag = nil

            # do different things based on stage
            if stage == :production
                fromTag = last_production_tag
            elsif stage == :staging
                fromTag = last_staging_tag
            else
                raise "Unsupported stage #{stage}"
            end

            begin
                toTag = tag
            rescue
                puts "Calculating 'end' tag for :update_log for '#{stage}'"
                # do different things based on stage
                if stage == :production
                    toTag = last_staging_tag
                elsif stage == :staging
                    toTag = 'head'
                else
                    raise "Unsupported stage #{stage}"
                end
            end

            # run comp
            logSubcommand = 'log'
            if ENV['git_log_command'] && ENV['git_log_command'].strip != ''
                logSubcommand = ENV['git_log_command']
            end
            command = "git #{logSubcommand} #{fromTag}..#{toTag}"
            puts command
            system command
        end

        desc "Mark the current code as a staging/qa release"
        task :tag_staging do
            # find latest staging tag for today
            newTagDate = Date.today.to_s 
            newTagSerial = 1

            # @todo refactor to use last_tag_matching
            todaysStagingTags = `git tag -l 'staging-#{newTagDate}.*'`
            todaysStagingTags = todaysStagingTags.split

            natcmpSrc = File.join(File.dirname(__FILE__), '/natcmp.rb')
            require natcmpSrc
            todaysStagingTags.sort! do |a,b|
                String.natcmp(b,a,true)
            end
            
            lastStagingTag = nil
            if todaysStagingTags.length > 0
                lastStagingTag = todaysStagingTags[0]

                # calculate largest serial and increment
                lastStagingTag =~ /staging-[0-9]{4}-[0-9]{2}-[0-9]{2}\.([0-9]*)/
                newTagSerial = $1.to_i + 1
            end
            newStagingTag = "staging-#{newTagDate}.#{newTagSerial}"

            shaOfCurrentCheckout = `git log --format=format:%H HEAD -1`
            shaOfLastStagingTag = nil
            if lastStagingTag
                shaOfLastStagingTag = `git log --format=format:%H #{lastStagingTag} -1`
            end

            if shaOfLastStagingTag == shaOfCurrentCheckout
                puts "Not re-tagging staging because the most recent tag (#{lastStagingTag}) already points to current head"
                newStagingTag = lastStagingTag
            else
                puts "Tagging current branch for deployment to staging as '#{newStagingTag}'"
                system "git tag -a -m 'tagging current code for deployment to staging' #{newStagingTag}"
            end

            set :branch, newStagingTag
        end

        desc "Push the passed staging tag to production. Pass in tag to deploy with '-s tag=staging-YYYY-MM-DD.X'."
        task :tag_production do
            if !exists? :tag
                raise "staging tag required; use '-s tag=staging-YYYY-MM-DD.X'"
            end

            # get list of staging tags
            # @todo refactor to use last_tag_matching
            todaysStagingTags = `git tag -l 'staging-*' | sort -rn`
            todaysStagingTags = todaysStagingTags.split


            if !todaysStagingTags.include? tag
                raise "Staging Tag #{tag} does not exist."
            end
            
            tag =~ /staging-([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]*)/
            newProductionTag = "production-#{$1}"
            puts "promoting staging tag #{tag} to production as '#{newProductionTag}'"
            system "git tag -a -m 'tagging current code for deployment to production' #{newProductionTag} #{tag}"

            set :branch, newProductionTag
        end
    end
end