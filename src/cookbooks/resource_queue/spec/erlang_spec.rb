# frozen_string_literal: true

require 'spec_helper'

describe 'resource_queue::erlang' do
  context 'installs erlang' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'installs the erlang runtime' do
        expect(chef_run).to include_recipe('erlang::default')
    end
  end
end
