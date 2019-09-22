# Example configuration

Here is an example using Microsoft's favourite make-believe company Contoso.

Their Azure AD tenant is: contoso.onmicrosoft.com

Look at *Office365 Group Sync.config.json.example* to see how this could be implemented.

## Users

Contoso has the following users:
- SysAdmin@contoso.com
- Bookkeeper@contoso.com
- BusinessManager@contoso.com
- Director@contoso.com
- ExecutiveAssistant@contoso.com
- FinanceManager@contoso.com
- GraphicDesigner@contoso.com
- MarketingManager@contoso.com
- SalesManager@contoso.com
- SalesPersonA@contoso.com
- SalesPersonB@contoso.com

## SharePoint sites

Contoso has the following SharePoint sites that are managed using Office 365 groups:
- Board Information
- Clients
- Design Files
- Management
- Promotions
- Suppliers

## Existing groups

Contoso has the following distribution groups:
- All Users
- Executives
- Finance Team
- Managers
- Marketing Team
- Sales Team

## Distribution group membership

All Users:
- Executives
- Finance Team
- Managers
- Marketing Team
- Sales Team
- ExecutiveAssistant@contoso.com

Executives:
- BusinessManager@contoso.com
- Director@contoso.com

Finance Team:
- Bookkeeper@contoso.com
- FinanceManager@contoso.com

Managers:
- BusinessManager@contoso.com
- FinanceManager@contoso.com
- MarketingManager@contoso.com
- SalesManager@contoso.com

Marketing Team:
- GraphicDesigner@contoso.com
- MarketingManager@contoso.com

Sales Team:
- SalesManager@contoso.com
- SalesPersonA@contoso.com
- SalesPersonB@contoso.com

## SharePoint site access

Board Information:
- Executives
- ExecutiveAssistant@contoso.com

Clients:
- Executives
- Finance Team
- Sales Team

Design Files:
- Marketing Team

Management:
- Executives
- Managers
- ExecutiveAssistant@contoso.com

Promotions:
- All Users

Suppliers:
- Executives
- Finance Team
- SalesManager@contoso.com

## Additional Information

The following rules also apply to Contoso:
- So that they can complete any executive task the Executives group must have access to all SharePoint sites.
- So that they can manage and provide support the SysAdmin@contoso.com must have access to all SharePoint sites.