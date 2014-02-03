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


Trello.configure do |config|
  config.developer_public_key = TRELLO_DEVELOPER_PUBLIC_KEY
  config.member_token = TRELLO_MEMBER_TOKEN
end

Asana.configure do |client|
  client.api_key = ASANA_API_KEY
end

board = Trello::Board.all.find { |b| b.name == 'ouk DB Tasks' }

workspace = Asana::Workspace.all.find { |w| w.name == 'ОУК' }

project = workspace.projects.find { |p| p.name == 'trello-se' }

puts "Migrate Trello board \"#{board.name}\" to Asana wokspace \"#{workspace.name}\", project \"#{project.name}\""

puts ' -- Getting users --'
users = workspace.users

board.lists.each do |list|

  next if list.name.downcase.include? 'done'

  puts " - #{list.name}:"

  list.cards.reverse.each do |card|
    puts "  - Card #{card.name}"

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
        u.name == 'Евгений Сковородин'
      }
      t.assignee = userList[0].id unless userList.empty?
    end

    task = workspace.create_task(t.attributes)

    #Project
    task.add_project(project.id)


    #Stories / Trello comments
    comments = card.actions.select {|a| a.type.downcase.include? 'commentcard' }
    comments.each do |c|

      task.create_story({:text => "#{c.member_creator.full_name}: #{c.data['text']}"}) unless c.data['text'].nil?

    end

    card.attachments.each do |att|

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

