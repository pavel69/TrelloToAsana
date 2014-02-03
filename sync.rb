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

Asana.configure do |client|
  client.api_key = ASANA_API_KEY
end

workspaces = Asana::Workspace.all

board = Trello::Board.all.find { |b| b.name == 'asana' }

workspace = Asana::Workspace.all.find { |w| w.name == 'ОУК' }

project = workspace.projects.all.find { |p| p.name == 'trello' }

puts "Migrate Trello board \"#{board.name}\" to Asana wokspace \"#{workspace.name}\", project \"#{project.name}\""


list = board.lists.all.find { |l| l.name == 'ToDo' }
list_doing = board.lists.all.find { |l| l.name == 'Doing' }


list.cards.reverse.each do |card|
  puts "  - Card #{card.name}"

  cardDir = Dir.home() + '/trello/' +  card.id

  # Create the task
  t = Asana::Task.new
  t.name = card.name
  t.notes = card.desc
  t.due_on = card.due.to_date if !card.due.nil?
  t.assignee = nil

  task = workspace.create_task(t.attributes)

  #Project
  task.add_project(project.id)

  task.create_story({:text => card.url}) unless card.url.nil?

  #Stories / Trello comments
  comments = card.actions.select {|a| a.type.include? 'ommentCard' }
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

  card.move_to_list(list_doing)
end
