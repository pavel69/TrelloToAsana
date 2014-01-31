#!/usr/bin/env ruby

require 'fileutils'
require 'open-uri'
require 'trello'
require 'asana'
require 'yaml'

cnf = YAML::load(File.open('config.yml'))

 
# Trello keys
TRELLO_DEVELOPER_PUBLIC_KEY = cnf['trello']['developer_public_key']
TRELLO_MEMBER_TOKEN = cnf['trello']['member_token']

# Asana keys
ASANA_API_KEY = cnf['asana']['api_key']
ASANA_ASSIGNEE = 'me'
 

def get_option_from_list(list, title, attribute)
  i=0

  while i == 0 do
    puts title
    
    list.each do |item|
      i += 1
      puts "  #{i}) #{item.send(attribute)}"
    end

    i = gets.chomp.to_i
    i = 0 if i <= 0 && i > list.size    
  end
  return i - 1
end
 

Trello.configure do |config|
  config.developer_public_key = TRELLO_DEVELOPER_PUBLIC_KEY
  config.member_token = TRELLO_MEMBER_TOKEN
end

Asana.configure do |client|
  client.api_key = ASANA_API_KEY
end

workspaces = Asana::Workspace.all

boards = Trello::Board.all
boards.each do |board|
  next if board.closed?
  
  #puts "\n=== Export Board #{board.name}? [yn]"
  next unless board.name == 'ouk2'

  # Which workspace to put it in
  workspace = workspaces[1]
  #workspace = workspaces[get_option_from_list(workspaces,
  #  "Select destination workplace",
  #  "name")]
  puts "Using workspace #{workspace.name}"

  # Which project to associate
  project = workspace.projects[3]



  #project = workspace.projects[get_option_from_list(workspace.projects,
  #  "Select destination project",
  #  "name")]
  puts " -- Using project #{project.name} --"

  puts ' -- Getting users --'
  users = workspace.users

  board.lists.each do |list|
  
    puts " - #{list.name}:"

    project = workspace.create_project({name: "trello-#{list.name}"})
    puts " -- Using project #{project.name} --"

    list.cards.reverse.each do |card|
      puts "  - Card #{card.name}, Due on #{card.due}"

      cardDir = Dir.home() + '/trello/' +  card.id

      # Create the task
      t = Asana::Task.new
      t.name = card.name
      t.notes = card.desc
      t.due_on = card.due.to_date if !card.due.nil?


      # Assignee - Try to find by name. Otherwise will be empty
      t.assignee = nil
      if !card.member_ids.empty? then
        userList = users.select { |u| 
          u.name == card.members[0].full_name
        }
        t.assignee = userList[0].id unless userList.empty?
      end

      task = workspace.create_task(t.attributes)
      
      #Project
      task.add_project(project.id)

      trello_users = ''

      comments = card.actions.select {|a| a.type.include? 'reateCard' }
      trello_users = "TA: #{comments[0].member_creator.full_name}; " unless comments.empty?


      if !card.members.empty? then
        trello_users += 'TM: ' + card.members.map { |v| v.full_name }.join(",")
      end

      task.create_story({:text => trello_users}) unless trello_users.empty?


      #Stories / Trello comments
      comments = card.actions.select {|a| a.type.include? 'ommentCard' }
      comments.each do |c|

        task.create_story({:text => "#{c.member_creator.full_name}: #{c.data['text']}"}) unless c.data['text'].nil?

      end

      card.attachments.each do |att|

        puts "\n=== Attachment #{att.name} #{att.url}"

        FileUtils.mkdir_p( cardDir )

        fn = cardDir + '/' + att.name
        File.open(fn, 'wb') do |saved_file|
          open(att.url, "rb") do |read_file|
            saved_file.write(read_file.read)

            request = RestClient::Request.new(
                :method => :post,
                :url => "https://app.asana.com/api/1.0/tasks/#{task.id}/attachments",
                :user => ASANA_API_KEY,
                :payload => {
                    :multipart => true,
                    :file => File.new(saved_file, 'rb')
                })
            response = request.execute


          end
        end

      end

      #Subtasks
      card.checklists.each do |checklist|
        checklist.check_items.each do |checkItem|
          st = Asana::Task.new
          st.name = checkItem['name']
          st.assignee = nil
          task.create_subtask(st.attributes)
        end
      end


    end

     # Create each list as an aggregator if it has cards in it
    if !list.cards.empty? then
      task = workspace.create_task({name: "#{list.name}:", assignee: nil})
      task.add_project(project.id)
    end


  end

  
end
