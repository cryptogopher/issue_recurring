# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

resources :issues do
    shallow do
      resources :recurrences, :controller => 'issue_recurrences', :only => [:create, :destroy]
    end
end
