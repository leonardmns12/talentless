require "ferrum"
require "http"
require_relative "setting.rb"

def print_or_hush(message)
  return if Setting::HUSH_HUSH
  print(message)
end

def puts_or_hush(message)
  return if Setting::HUSH_HUSH
  puts(message)
end

def base_url(path = nil)
  "https://hr.talenta.co#{path}"
end

def login_failed?(page)
  !page.at_css(".alert.alert-danger").nil?
end

def still_loading?(page)
  page.frames.any? { |f| f.state != :stopped_loading }
end

def wait_until
  loop do
    break if yield
    sleep 1
  end
end

def wait_until_no_error
  loop do
    begin
      yield
      break
    rescue
      print_or_hush "."
    end
  end
end

def current_time
  Time.now.getlocal(Setting::TIME_ZONE)
end

def send_to_slack(message)
  return if Setting::SLACK_WEBHOOK.empty?
  HTTP.post(Setting::SLACK_WEBHOOK, json: {username: "Github Action", avatar_url: "https://i.imgur.com/4M34hi2.png", "embeds": [
    {
      "author": {
        "name": "Automate Absence Report",
        "url": "https://www.reddit.com/r/cats/",
        "icon_url": "https://i.imgur.com/BJSvIVH.png"
      },
      "title": "Daily Report for Leo",
      "description": message,
      "color": 15258703,
      "fields": [
        {
          "name": "Latitude",
          "value": "-6.200304570458018",
          "inline": true
        },
        {
          "name": "Longitude",
          "value": "106.61325634009492",
          "inline": true
        },
        {
          "name": "Sended to cc mail",
          "value": "leonard.monosa@gambitstocks.com \n leonard.monosa@stockbit.com \n leonardmanoza@gmail.com"
        },
        {
          "name": "Thanks!",
          "value": "You're welcome :wink:"
        }
      ],
      "footer": {
        "text": "Coded with ❤️ by Leo",
        "icon_url": "https://i.imgur.com/BJSvIVH.png"
      }
    }
  ]})
end

def run
  if current_time.saturday? or current_time.sunday?
    return "Enjoy your weekend, that's an order!"
  end

  # browser = Ferrum::Browser.new(headless: Setting::HEADLESS, window_size: [3840, 2160])
  browser = Ferrum::Browser.new(headless: Setting::HEADLESS, window_size: [1680, 1050])
  context = browser.contexts.create
  page = context.create_page

  puts_or_hush "Spoofing geolocation #{Setting::LATITUDE}, #{Setting::LONGITUDE}"
  page.command("Browser.grantPermissions", permissions: ["geolocation"], origin: base_url, browserContextId: context.id)
  page.command("Page.setGeolocationOverride", latitude: Setting::LATITUDE, longitude: Setting::LONGITUDE, accuracy: 100)

  page.go_to(base_url)

  print_or_hush "Logging in as `#{Setting::EMAIL}`..."

  email_input = page.at_css("input#user_email")
  email_input.focus.type(Setting::EMAIL)

  password_input = page.at_css("input#user_password")
  password_input.focus.type(Setting::PASSWORD)

  previous_url = page.current_url

  sign_in_button = page.at_css("#new-signin-button")
  sign_in_button.click

  wait_until do
    login_failed?(page) or
      (page.current_url != previous_url and not still_loading?(page))
  end

  if login_failed?(page)
    raise "Login failed."
  end

  puts_or_hush "We're in."

  print_or_hush "Checking whether we take days off..."

  time_offs = [current_time.month - 1, current_time.month].reduce([]) do |acc, month|
    page.go_to(base_url("/my-info/time-off?monthCompare=#{month.to_s.rjust(2, "0")}&yearCompare=#{current_time.year}"))
    
    wait_until_no_error do
      page.at_css("#timeOffHistory_length").click
      page.css("#timeOffHistory_length ul li").find {|li| li.inner_text == "All" }.click
    end

    header = page.css("table#timeOffHistory thead th").map(&:inner_text)

    acc + page.css("table#timeOffHistory tbody tr").map do |tr|
      time_off = header.zip(tr.css("td").map(&:inner_text)).to_h

      if time_off["Start Date"].nil?
        nil
      else
        start_date = Time.parse(time_off["Start Date"], current_time)
        end_date = Time.parse("#{time_off["End Date"]} 23:59:59", current_time) # let's throw leap seconds to the sea
        
        {
          range: start_date..end_date,
          effective: time_off["Status"] == "Approved" && time_off["Canceled"] == "-"
        }
      end
    end.compact
  end

  time_off_today = time_offs.find { |t| t[:effective] && t[:range].include?(current_time) }

  if time_off_today
    send_to_slack("We have days offfff Leo!!! :wink: #{time_off_today}")
    return "We have days offfff!!! #{time_off_today}"
  else
    puts_or_hush "Nope, no day off today."
  end

  page.go_to(base_url("/live-attendance"))

  wait_until { page.at_css("#tl-live-attendance-index")&.inner_text.to_s.match?(/Loading/) }
  wait_until { !page.at_css("#tl-live-attendance-index")&.inner_text.to_s.match?(/Loading/) }

  holiday = page.at_css(".schedule-time__type")&.inner_text&.strip
  return "Day off: #{holiday}" if holiday != "N"

  log =
    if page.at_css(".tl-blankslate").nil?
      page.css("#tl-live-attendance-index ul li").map { |li| li.inner_text.split("\n\n").take(2) }
    else
      []
    end

  if not log.empty?
    puts_or_hush "\nLog:"
    log.each do |i|
      puts_or_hush i.join(": ")
    end
    puts_or_hush ""
  end

  _last_time, last_action = log.last

  case last_action
  when nil
    puts_or_hush "Clocking in..."
    clock_in_button = page.css("button").find { |b| b.inner_text == "Clock In" }
    clock_in_button.click
    send_to_slack("I'm successfuly clocked in for Leo :wink:")
    return "Clocked in."
  when "Clock In"
    puts_or_hush "Clocking out..."
    clock_out_button = page.css("button").find { |b| b.inner_text == "Clock Out" }
    clock_out_button.click
    send_to_slack("I'm successfuly clocked out for you today Leo :wink:")
    return "Clocked out."
  when "Clock Out"
    send_to_slack('Already clocked out today for Leo :wink:')
    return "All good today."
  else
    raise "I don't know what's going on."
  end
end

start_time = current_time

begin
  result_message = run
  puts_or_hush result_message
rescue => error
  send_to_slack("#{error.message} :frowning:")
  raise error
end

if Setting::HUSH_HUSH && (current_time - start_time) < 180
  sleep 180 - (current_time - start_time)
end
