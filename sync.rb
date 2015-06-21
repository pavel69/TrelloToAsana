#!/usr/bin/env ruby

require 'fileutils'
require 'open-uri'
require 'trello'
require 'asana'
require 'yaml'
require 'pp'
require 'ap'

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

asana = Asana::Client.new do |c|
  c.authentication :api_token, ASANA_API_KEY
end

board = Trello::Board.all.find { |b| b.name == 'asana' }

workspace = asana.workspaces.find_all.find { |w| w.name == 'ОУК' }

project = asana.projects.find_all(workspace: workspace.id).find { |p| p.name == 'trello' }

puts "Migrate Trello board \"#{board.name}\" to Asana wokspace \"#{workspace.name}\", project \"#{project.name}\""


list = board.lists.find { |l| l.name == 'ToDo' }
list_doing = board.lists.find { |l| l.name == 'Doing' }


list.cards.reverse.each do |card|

  puts "  - Card #{card.name}"

  cardDir = Dir.home() + '/trello/' +  card.id

  # Create the task
#  t = Asana::Task.new
#  t.name = card.name
#  t.notes = card.desc
#  t.due_on = card.due.to_date if !card.due.nil?

  task = asana.tasks.create({ name: card.name, notes: card.desc, projects: [ project.id ], workspace: workspace.id})

  asana.stories.create_on_task(task: task.id, text: card.url) unless card.url.nil?

  #Stories / Trello comments
  comments = card.actions.select {|a| a.type.include? 'ommentCard' }

  comments.each do |c|
    asana.stories.create_on_task(task: task.id, text: "#{c.member_creator.full_name}: #{c.data['text']}") unless c.data['text'].nil?
  end

  card.attachments.each do |att|

    if att.is_upload

      FileUtils.mkdir_p( cardDir )

      fn = cardDir + '/' + att.name.gsub(/[\/:]/, '_')

      File.open(fn, 'wb') do |saved_file|
        open(att.url, 'rb') do |read_file|
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

    else
      asana.stories.create_on_task(task: task.id, text: att.url) unless att.url.nil?
    end

  end

=begin
  #Subtasks
  card.checklists.each do |checklist|
    checklist.check_items.each do |checkItem|
      st = Asana::Task.new
      st.name = checkItem['name']
      st.assignee = nil
      task.create_subtask(st.attributes)
    end
  end
=end

  card.move_to_list(list_doing)
end
