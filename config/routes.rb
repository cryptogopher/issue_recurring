# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

resources :issues, shallow_prefix: :issue do
  shallow do
    resources :recurrences, controller: :issue_recurrences, except: [:index, :show]
  end
end
resources :projects do
  shallow do
    resources :recurrences, controller: :issue_recurrences, only: [:index]
  end
end
