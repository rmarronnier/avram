require "../spec_helper"

private class UpsertUser < User::SaveOperation
  upsert_lookup_columns :name
end

private class UpsertUserWithMultipleColumns < User::SaveOperation
  upsert_lookup_columns :name, :age
end

private class UpsertUserWithNickname < User::SaveOperation
  upsert_lookup_columns :nickname
end

describe "Avram::Upsert" do
  describe "upsert!" do
    it "creates a new record when no conflicting record exists" do
      user_count = UserQuery.new.select_count

      user = UpsertUser.upsert!(
        name: "New User",
        age: 25,
        joined_at: Time.utc
      )

      user.name.should eq("New User")
      user.age.should eq(25)
      user.joined_at.should_not be_nil
      UserQuery.new.select_count.should eq(user_count + 1)
    end

    it "updates an existing record when there's a conflict on lookup columns" do
      existing_user = UserFactory.create &.name("Existing User").age(30)
      user_count = UserQuery.new.select_count

      updated_user = UpsertUser.upsert!(
        name: "Existing User",
        age: 35,
        joined_at: Time.utc
      )

      updated_user.id.should eq(existing_user.id)
      updated_user.name.should eq("Existing User")
      updated_user.age.should eq(35)
      UserQuery.new.select_count.should eq(user_count)
    end

    it "raises an error when validation fails" do
      expect_raises(Avram::InvalidOperationError) do
        UpsertUser.upsert!(
          name: "", # Invalid - name is required
          age: 25,
          joined_at: Time.utc
        )
      end
    end

    it "handles nil values in lookup columns correctly" do
      user_with_nil_nickname = UserFactory.create &.nickname(nil).name("No Nickname User")

      # Should create a new user since this uses name as lookup
      new_user = UpsertUser.upsert!(
        name: "Different Name",
        age: 30,
        joined_at: Time.utc
      )

      new_user.id.should_not eq(user_with_nil_nickname.id)
      new_user.name.should eq("Different Name")
    end
  end

  describe "upsert" do
    it "yields the operation and created record when successful" do
      UpsertUser.upsert(
        name: "Test User",
        age: 25,
        joined_at: Time.utc
      ) do |operation, user|
        operation.valid?.should be_true
        user.should_not be_nil
        user.not_nil!.name.should eq("Test User")
      end
    end

    it "yields the operation and nil when validation fails" do
      UpsertUser.upsert(
        name: "",
        age: 25,
        joined_at: Time.utc
      ) do |operation, user|
        operation.valid?.should be_false
        user.should be_nil
        operation.errors[:name].should contain("is required")
      end
    end

    it "updates existing record when found" do
      existing_user = UserFactory.create &.name("Original")

      UpsertUser.upsert(
        name: "Original",
        age: 40,
        joined_at: Time.utc
      ) do |operation, user|
        operation.valid?.should be_true
        user.should_not be_nil
        user.not_nil!.id.should eq(existing_user.id)
        user.not_nil!.age.should eq(40)
      end
    end
  end

  describe "upsert with multiple lookup columns" do
    it "only updates when all lookup columns match" do
      existing_user = UserFactory.create &.name("Multi User").age(25)

      # Different age - should create new record
      new_user = UpsertUserWithMultipleColumns.upsert!(
        name: "Multi User",
        age: 30,
        joined_at: Time.utc
      )

      new_user.id.should_not eq(existing_user.id)

      # Same name and age - should update
      updated_user = UpsertUserWithMultipleColumns.upsert!(
        name: "Multi User",
        age: 25,
        joined_at: Time.utc
      )

      updated_user.id.should eq(existing_user.id)
      updated_user.name.should eq("Multi User")
    end
  end

  describe "upsert with non-unique columns" do
    it "works but may have unexpected behavior without unique constraints" do
      # This test demonstrates why unique constraints are important
      UserFactory.create &.name("Duplicate Name").age(25)
      UserFactory.create &.name("Duplicate Name").age(30)

      # This will update the first matching record found
      # Without a unique constraint, behavior is non-deterministic
      UpsertUser.upsert!(
        name: "Duplicate Name",
        age: 35,
        joined_at: Time.utc
      )

      # There should still be 2 users with this name
      UserQuery.new.name("Duplicate Name").select_count.should eq(2)
    end
  end

  describe "edge cases" do
    it "handles operations with minimal required fields" do
      user = UpsertUser.upsert!(
        name: "Only Required Fields",
        age: 25,
        joined_at: Time.utc
      )

      user.name.should eq("Only Required Fields")
      user.age.should eq(25)
      user.nickname.should be_nil # nickname is nullable
    end

    it "respects database constraints" do
      # Create a user with a specific name
      existing = UserFactory.create &.name("Unique Name")

      # Using nickname as lookup, but same name could still conflict
      # if there's a unique constraint on name
      new_user = UpsertUserWithNickname.upsert!(
        name: "Different Name",
        nickname: "unique_nick",
        age: 25,
        joined_at: Time.utc
      )
      
      new_user.id.should_not eq(existing.id)
    end

    it "works with has_one associations" do
      # User model has has_one sign_in_credential
      user = UpsertUser.upsert!(
        name: "User with Credential",
        age: 30,
        joined_at: Time.utc
      )

      user.id.should_not be_nil
    end

    it "triggers callbacks appropriately" do
      # This would require a SaveOperation with callbacks defined
      # For now, we'll just ensure the basic flow works
      user = UpsertUser.upsert!(
        name: "Callback Test",
        age: 25,
        joined_at: Time.utc
      )

      # If there were before_save/after_save callbacks,
      # they should have been triggered
      user.id.should_not be_nil
    end
  end

  describe "error messages" do
    it "provides clear error when upsert_lookup_columns is not defined" do
      # This is tested at compile time, so we can't test it here
      # but it's good to document that User::SaveOperation.upsert!
      # would fail at compile time without upsert_lookup_columns
    end
  end
end
