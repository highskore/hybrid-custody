import "HybridCustody"

import "CapabilityFactory"
import "CapabilityDelegator"
import "CapabilityFilter"

import "MetadataViews"

transaction() {
    prepare(childAcct: AuthAccount, parentAcct: AuthAccount) {
        // --------------------- Begin setup of child account ---------------------
        var acctCap = childAcct.getCapability<&AuthAccount>(HybridCustody.LinkedAccountPrivatePath)
        if !acctCap.check() {
            acctCap = childAcct.linkAccount(HybridCustody.LinkedAccountPrivatePath)!
        }

        if childAcct.borrow<&HybridCustody.OwnedAccount>(from: HybridCustody.OwnedAccountStoragePath) == nil {
            let ownedAccount <- HybridCustody.createOwnedAccount(acct: acctCap)
            childAcct.save(<-ownedAccount, to: HybridCustody.OwnedAccountStoragePath)
        }

        // check that paths are all configured properly
        childAcct.unlink(HybridCustody.OwnedAccountPrivatePath)
        childAcct.link<&HybridCustody.OwnedAccount{HybridCustody.BorrowableAccount, HybridCustody.OwnedAccountPublic, MetadataViews.Resolver}>(HybridCustody.OwnedAccountPrivatePath, target: HybridCustody.OwnedAccountStoragePath)

        childAcct.unlink(HybridCustody.OwnedAccountPublicPath)
        childAcct.link<&HybridCustody.OwnedAccount{HybridCustody.OwnedAccountPublic, MetadataViews.Resolver}>(HybridCustody.OwnedAccountPublicPath, target: HybridCustody.OwnedAccountStoragePath)
        // --------------------- End setup of child account ---------------------

        // --------------------- Begin setup of parent account ---------------------
        var filter: Capability<&{CapabilityFilter.Filter}>? = nil

        if parentAcct.borrow<&HybridCustody.Manager>(from: HybridCustody.ManagerStoragePath) == nil {
            let m <- HybridCustody.createManager(filter: nil)
            parentAcct.save(<- m, to: HybridCustody.ManagerStoragePath)
        }

        parentAcct.unlink(HybridCustody.ManagerPublicPath)
        parentAcct.unlink(HybridCustody.ManagerPrivatePath)

        parentAcct.link<&HybridCustody.Manager{HybridCustody.ManagerPrivate, HybridCustody.ManagerPublic}>(HybridCustody.OwnedAccountPrivatePath, target: HybridCustody.ManagerStoragePath)
        parentAcct.link<&HybridCustody.Manager{HybridCustody.ManagerPublic}>(HybridCustody.ManagerPublicPath, target: HybridCustody.ManagerStoragePath)
        // --------------------- End setup of parent account ---------------------

        // Publish account to parent
        let owned = childAcct.borrow<&HybridCustody.OwnedAccount>(from: HybridCustody.OwnedAccountStoragePath)
            ?? panic("owned account not found")

        // create and save resource, if not exist
        if parentAcct.borrow<&AnyResource>(from: CapabilityFactory.StoragePath) == nil {
            prrentAcc.save(<- CapabilityFactory.createFactoryManager(), to: CapabilityFactory.StoragePath)
        }

        var factory = parentAcct.capabilities.get<&CapabilityFactory.Manager{CapabilityFactory.Getter}>(CapabilityFactory.PublicPath)
        if factory == nil || factory?.check() == false {
            parentAcct.capabilities.unpublish(CapabilityFactory.PublicPath)
            factory = parentAcct.capabilities.storage
                .issue<&CapabilityFactory.Manager{CapabilityFactory.Getter}>(CapabilityFactory.StoragePath)
            parentAcct.capabilities.publish(factory!, at: CapabilityFactory.PublicPath)
            }

        assert(factory.check(), message: "factory address is not configured properly")

        // create and save resource, if not exist
        if parentAcc.borrow<&AnyResource>(from: CapabilityFilter.StoragePath) == nil {
            parentAcc.save(<- CapabilityFilter.create(Type<@CapabilityFilter.AllowAllFilter>()), to: CapabilityFilter.StoragePath)
        }

        var filterForChild  = parentAcc.capabilities.get<&{CapabilityFilter.Filter}>(CapabilityFilter.PublicPath)
        if filterForChild  == nil || filterForChild ?.check() == false {
            parentAcc.capabilities.unpublish(CapabilityFilter.PublicPath)
            filterForChild  = parentAcc.capabilities.storage
                .issue<&AnyResource{CapabilityFilter.Filter}>(CapabilityFilter.StoragePath)
            parentAcc.capabilities.publish(filterForChild !, at: CapabilityFilter.PublicPath)
        }

        assert(filterForChild.check(), message: "capability filter is not configured properly")

        owned.publishToParent(parentAddress: parentAcct.address, factory: factory, filter: filterForChild)

        // claim the account on the parent
        let inboxName = HybridCustody.getChildAccountIdentifier(parentAcct.address)
        let cap = parentAcct.inbox.claim<&HybridCustody.ChildAccount{HybridCustody.AccountPrivate, HybridCustody.AccountPublic, MetadataViews.Resolver}>(inboxName, provider: childAcct.address)
            ?? panic("child account cap not found")

        let manager = parentAcct.borrow<&HybridCustody.Manager>(from: HybridCustody.ManagerStoragePath)
            ?? panic("manager no found")

        manager.addAccount(cap: cap)
    }
}